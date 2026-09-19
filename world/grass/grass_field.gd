extends Node
## 草场（Autoload）—— 全图「活着的草」的唯一持有者与推进者（世界状态，与 GridManager 同级）。
##
## 职责边界（保持薄、只干草的事）：
##   - 持有 tiles: coord -> GrassTile（只存"有草"的格，不扫全 16900 图）。
##   - 订阅 TimeSystem.tick，按 dt(游戏分) 推进【再生】与【扩散】。
##   - 对外只暴露查询/交互：is_edible / bite / edible_nearest / ratio_of …，供猪(Grazing)与表现层用。
## 不认识生物、不认识 UI：猪通过 Grazing 组件调它的接口，渲染层读它的状态重画。
##
## 与地形的分工：`Cell.terrain` 是**静态基底**（unknown/grass/tall_grass：决定 plantable、隐蔽、色底）；
##   GrassField.tiles 是**活的草量**（有没有可食草、还剩几口）。扩散只在 Terrain.plantable 的格上新生长草，
##   **不改 Cell.terrain**（避免 terrain_changed 全图重烘），渲染层叠加读 GrassField。
##
## 可复现：扩散/选格的随机源 = rng（seed = WorldSeed.value）→ 同种子同一部草场演化。

const GRASS_DEF: GrassDef = preload("res://world/grass/grass_common.tres")

var tiles: Dictionary = {}                 # Vector2i -> GrassTile
var rng := RandomNumberGenerator.new()     # 草场专用随机源（扩散/选格），与生物个体 RNG 分离

func _ready() -> void:
	rng.seed = WorldSeed.value
	TimeSystem.tick.connect(_on_tick)

## 启动时按地形的"草基底"格播种一批成熟草（grassland_generator 已把椭圆区标成 grass/tall_grass）。
## 由 Main 在 generate 之后调用一次。
func seed_existing(grid: Grid) -> void:
	tiles.clear()
	for y in grid.height:
		for x in grid.width:
			var cell := grid.get_cell(Vector2i(x, y))
			if cell == null:
				continue
			if cell.terrain == Terrain.GRASS or cell.terrain == Terrain.TALL_GRASS:
				_establish(Vector2i(x, y), GRASS_DEF.max_bites)

# ---------------- 每帧推进 ----------------
func _on_tick(dt: float) -> void:
	# 先收集要扩散出的新格（遍历中不修改 tiles，避免迭代器失效）
	var to_add: Array[Vector2i] = []
	for coord in tiles.keys():
		var t: GrassTile = tiles[coord]
		_recover(t, dt)
		if t.is_mature():
			_collect_spread(t, dt, to_add)
	for c in to_add:
		_establish(c, GRASS_DEF.seed_bites)
		EventBus.grass_established.emit(c)
		EventBus.grass_changed.emit(c)

## 再生：耐久未到顶就累计；归 0（秃）后按 depleted_extra_penalty 倍慢（伤根）。
func _recover(t: GrassTile, dt: float) -> void:
	if t.durability >= t.def.max_bites:
		t._recover_acc = 0.0
		return
	# 草只在**白天**生长：夜里不再生（用户拍板）
	if TimeSystem.is_night():
		return
	var rate := 1.0 / t.def.recover_per_bite_min
	if t.durability <= 0:
		rate /= maxf(t.def.depleted_extra_penalty, 0.0001)
	var before := t.durability
	t._recover_acc += dt * rate
	while t._recover_acc >= 1.0 and t.durability < t.def.max_bites:
		t._recover_acc -= 1.0
		t.durability += 1
	if t.durability != before:
		if t.durability >= t.def.max_bites:
			EventBus.grass_matured.emit(t.coord)
		EventBus.grass_changed.emit(t.coord)

## 扩散计时：成熟格到点则掷概率，在 3×3 邻域挑一个可定殖格。命中则加入 to_add。
func _collect_spread(t: GrassTile, dt: float, to_add: Array[Vector2i]) -> void:
	# 草只在**白天**生长/扩散：夜里停（用户拍板）
	if TimeSystem.is_night():
		return
	t._spread_acc += dt
	if t._spread_acc < t.def.spread_interval_min:
		return
	t._spread_acc = 0.0
	if rng.randf() >= t.def.spread_chance:
		return
	var spot := _pick_spread_target(t.coord, t.def.spread_radius)
	if spot.x >= 0:
		to_add.append(spot)

func _pick_spread_target(from: Vector2i, radius: int) -> Vector2i:
	var cands: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var c := from + Vector2i(dx, dy)
			if _can_colonize(c):
				cands.append(c)
	if cands.is_empty():
		return Vector2i(-1, -1)
	return cands[rng.randi_range(0, cands.size() - 1)]

## 可定殖：在界内 + 基底 plantable + 无占格 + 无尸体 + 当前没草。
func _can_colonize(c: Vector2i) -> bool:
	if not GridManager.in_bounds(c.x, c.y):
		return false
	if tiles.has(c):
		return false
	var cell := GridManager.cell_at(c.x, c.y)
	if cell == null or cell.content != null or cell.corpse != null:
		return false
	return Terrain.plantable(cell.terrain)

# ---------------- 交互：啃食 ----------------
## 唯一啃食入口。返回 {food_gained, water_gained, depleted}；不可食时增量为 0。
func bite(coord: Vector2i) -> Dictionary:
	var t: GrassTile = tiles.get(coord)
	if t == null or not t.is_edible():
		return {"food_gained": 0.0, "water_gained": 0.0, "depleted": false}
	t.durability -= 1
	t._recover_acc = 0.0
	var depleted := t.durability < t.def.edible_min_bites
	EventBus.grass_changed.emit(coord)
	if depleted:
		EventBus.grass_depleted.emit(coord)
	var food: float = t.def.food_per_bite
	var water: float = t.def.water_per_bite
	return {"food_gained": food, "water_gained": water, "depleted": depleted}

# ---------------- 查询 ----------------
func _establish(coord: Vector2i, dur: int) -> void:
	tiles[coord] = GrassTile.new(GRASS_DEF, coord, dur)

func has_grass(coord: Vector2i) -> bool:
	return tiles.has(coord)

func is_edible(coord: Vector2i) -> bool:
	var t: GrassTile = tiles.get(coord)
	return t != null and t.is_edible()

func is_mature(coord: Vector2i) -> bool:
	var t: GrassTile = tiles.get(coord)
	return t != null and t.is_mature()

## 着色/查询用：该格耐久比例；无草返回 -1（渲染层据此回落到地形色）。
func ratio_of(coord: Vector2i) -> float:
	var t: GrassTile = tiles.get(coord)
	return t.ratio() if t != null else -1.0

## 半径内最近的可食草格（供猪寻的）；没有返回 Vector2i(-1,-1)。
## 只遍历"有草的格"(tiles)，代价 ∝ 草格数而非半径² → 放大寻草半径也不卡。
func edible_nearest(from: Vector2i, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := float(radius * radius + 1)   # 只接受半径内（含半径）的；初值略大于半径²
	var r2 := float(radius * radius)
	for coord in tiles.keys():
		var t: GrassTile = tiles[coord]
		if not t.is_edible():
			continue
		var d := float((coord - from).length_squared())
		if d <= r2 and d < best_d:
			best_d = d
			best = coord
	return best

## 是否"嫩草"：可食 且 耐久未满（新生/再生中的幼嫩草）。猪优先吃这种。
func is_tender(coord: Vector2i) -> bool:
	var t: GrassTile = tiles.get(coord)
	return t != null and t.is_edible() and t.durability < t.def.max_bites

## 半径内**最嫩**（耐久最低）的可食草格；没有嫩草返回 (-1,-1)（猪就"算了"不吃）。
func tender_nearest(from: Vector2i, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dur := INF
	var r2 := float(radius * radius)
	for coord in tiles.keys():
		var t: GrassTile = tiles[coord]
		if not is_tender(coord):
			continue
		var d := float((coord - from).length_squared())
		if d <= r2 and float(t.durability) < best_dur:
			best_dur = float(t.durability)
			best = coord
	return best

func count() -> int:
	return tiles.size()

func count_mature() -> int:
	var n := 0
	for t in tiles.values():
		if (t as GrassTile).is_mature():
			n += 1
	return n

func debug_state(coord: Vector2i) -> String:
	var t: GrassTile = tiles.get(coord)
	if t == null:
		return "无草"
	return "草%d/%d" % [t.durability, t.def.max_bites]
