extends Node
## 全局网格管理器（Autoload）。任何代码都能直接引用，方便调试与编写：
##   GridManager.cell_at(0, 0)        -> 取到 (0,0) 这一格
##   GridManager.in_bounds(1, 0)      -> 是否越界
##   GridManager.occupy(c, who)       -> 占格（唯一写入口）
##   GridManager.release(c, who)      -> 释放（唯一写入口）
##   GridManager.random_free_cell()   -> 随机挑一个空格（O(1)，不扫全网格）
##   GridManager.terrain_cells(id)    -> 某个地形的全部格（派生缓存，O(1) 取表）
##   GridManager.grid.grid_to_world(...) 等坐标换算
##
## Cell.content 是生物占格事实，Cell.feature 是地物事实；不要绕过写入口修改。
## `_free` 从 can_enter() 派生，由占格、释放、地物放置/移除及地形重建同步。
## 同理 `_terrain_cells` 是 `Cell.terrain` 的**派生缓存**，只由 rebuild_terrain_index() 维护。

## 网格尺寸的**唯一来源**（Grid 自己不再给默认值，避免两处各写一份尺寸）
## 2026-09-19：40×24 -> **100×100**（草原环境）-> **130×130**。
##   扩到 130 是为了：草原中心改放在「离地图正中半径 50 的圆周」上随机取点后，
##   草块（长半轴 ~11 + 噪声）连中心一起仍能**整个落在图内**（中心到边 = 65 > 50 + 11.5）。
##   130 格 × 32px = 4160×4160 世界像素，仍靠可拖动/缩放相机（world/presentation/camera_rig.gd）观察。
const WIDTH := 130
const HEIGHT := 130

var grid: Grid
var _free: Dictionary = {}   # Vector2i -> true（空格集合，派生缓存）
var _terrain_exclusions: Dictionary = {}  # 格 -> {地形 id: 排除次数}

## 地形索引（派生缓存 2）：地形 id -> 该地形的全部格坐标。
## 【为什么要缓存】"最近的某地形格在哪"如果每次按半径扫 O(r²)，生物一多就撑不住。
##   地形只在启动时写一次 -> 建一次索引（O(地形种数 × 格数)，一次性），
##   之后每次查询代价 = **O(该地形的格数)**，**与搜索半径无关** -> 半径可以放心给大。
## 【唯一事实来源仍是 Cell.terrain】本表只是它的派生视图，绝不反向写。
##   ⚠ 地形改了却不发 `terrain_changed` -> 本索引过期。要改地形，就发那个信号。
var _terrain_cells: Dictionary = {}   # StringName -> PackedVector2Array

func _ready() -> void:
	grid = Grid.new(WIDTH, HEIGHT)
	# ⚠ 这里**不**填 `_free`：开局全部格都是空的，但那是"地形还没生成"的**暂时**状态，
	#   而 `_free` 按定义是"当前没有占格者的格"—— 两者不是一回事。
	#   地形生成完（main.gd 发 terrain_changed）后由 rebuild_terrain_index() 一并重建，
	#   那才是 `_free` 的正确时机与唯一写入口。
	rebuild_terrain_index()
	# GridManager 在 Autoload 顺序里排在 EventBus **之前** -> 此刻 EventBus 还没进树，连不上。
	# 延后到本帧末接线，并**补一次重建**：主场景的 _ready 会在接线之前就把地形生成好。
	_link_bus.call_deferred()

func _link_bus() -> void:
	if not EventBus.terrain_changed.is_connected(rebuild_terrain_index):
		EventBus.terrain_changed.connect(rebuild_terrain_index)
	rebuild_terrain_index()

func cell_at(x: int, y: int) -> Grid.Cell:
	return grid.get_cell(Vector2i(x, y))

func in_bounds(x: int, y: int) -> bool:
	return grid.in_bounds(Vector2i(x, y))

## 静态通行事实与动态占格分开；地物只通过 blocks_movement 协议参与。
func is_walkable(c: Vector2i) -> bool:
	var cell: Grid.Cell = grid.get_cell(c)
	return cell != null and Terrain.walkable(cell.terrain) \
		and (cell.feature == null or not bool(cell.feature.call("blocks_movement")))

func can_enter(c: Vector2i, who: Variant = null) -> bool:
	var cell: Grid.Cell = grid.get_cell(c)
	return is_walkable(c) and (cell.content == null or cell.content == who)

func place_feature(c: Vector2i, feature: RefCounted) -> bool:
	if feature == null or not feature.has_method("blocks_movement"):
		push_error("地物必须提供 blocks_movement 通行协议")
		return false
	var cell: Grid.Cell = grid.get_cell(c)
	if cell == null or cell.feature != null or not Terrain.walkable(cell.terrain):
		return false
	if bool(feature.call("blocks_movement")) and cell.content != null:
		return false
	cell.feature = feature
	_sync_free(c)
	return true

func remove_feature(c: Vector2i, feature: RefCounted) -> void:
	var cell: Grid.Cell = grid.get_cell(c)
	if cell != null and cell.feature == feature:
		cell.feature = null
		_sync_free(c)

func feature_at(c: Vector2i) -> RefCounted:
	var cell: Grid.Cell = grid.get_cell(c)
	return cell.feature if cell != null else null

## 树冠等外观范围可以排除草的扩散，仍只由根部决定通行。
func adjust_terrain_exclusion(c: Vector2i, terrain: StringName, change: int) -> void:
	var excluded: Dictionary = _terrain_exclusions.get(c, {})
	var count_value: int = int(excluded.get(terrain, 0)) + change
	assert(count_value >= 0, "地形排除必须成对释放")
	if count_value > 0:
		excluded[terrain] = count_value
	else:
		excluded.erase(terrain)
	if excluded.is_empty():
		_terrain_exclusions.erase(c)
	else:
		_terrain_exclusions[c] = excluded

func allows_terrain(c: Vector2i, terrain: StringName) -> bool:
	return grid.in_bounds(c) and int(_terrain_exclusions.get(c, {}).get(terrain, 0)) == 0

func _sync_free(c: Vector2i) -> void:
	if can_enter(c):
		_free[c] = true
	else:
		_free.erase(c)

## 生物占格入口：通行规则与移动、出生一致，拒绝水域、阻挡地物和其他占格者。
func occupy(c: Vector2i, who) -> bool:
	var cell := grid.get_cell(c)
	if not can_enter(c, who):
		return false
	cell.content = who
	_sync_free(c)
	return true

## 释放唯一入口。只放自己占的格（防止误清别人的）。
func release(c: Vector2i, who) -> void:
	var cell := grid.get_cell(c)
	if cell == null or cell.content != who:
		return
	cell.content = null
	_sync_free(c)

## 随机空格。没有空格返回 Vector2i(-1, -1)（用 x<0 判断）。
## 从 can_enter() 的派生缓存选择；不重复定义通行规则。
func random_free_cell() -> Vector2i:
	if _free.is_empty():
		return Vector2i(-1, -1)
	return _free.keys().pick_random()

## 空格数（调试 / 校验用）
func free_count() -> int:
	return _free.size()

# ---------------- 地形索引（派生缓存，2026-09-20） ----------------

## 重建地形索引。构造期自己调一次；此后由 `terrain_changed` 触发。代价 O(地形种数 × 格数)。
##
## 【为什么两趟扫而不是边扫边 append】Packed 数组是**按值传递（写时复制）**的：
##   往 `dict[key]` 里"就地 append"会改到一个临时副本上、丢掉结果（本项目踩过）。
##   两趟扫：先把地形种类收齐，再逐个地形建一个 PackedVector2Array 后**一次性写回** —— 没有中途修改。
func rebuild_terrain_index() -> void:
	var kinds: Dictionary = {}
	for c in grid.cells.keys():
		var cell: Grid.Cell = grid.cells[c]
		if cell == null:
			continue
		kinds[cell.terrain] = true
	var built: Dictionary = {}
	for t in kinds.keys():
		var arr := PackedVector2Array()
		for c in grid.cells.keys():
			var cell: Grid.Cell = grid.cells[c]
			if cell != null and cell.terrain == t:
				arr.append(Vector2(c))
		built[t] = arr
	_terrain_cells = built
	_rebuild_free()


## 全量重建；单格写入口统一调用 _sync_free()。
func _rebuild_free() -> void:
	_free.clear()
	for c in grid.cells.keys():
		_sync_free(c)

## 某个地形的全部格（只读视图；返回的是副本，调用方改不动缓存）。
## 没有这种地形 -> 空数组。查询"最近的某地形格"请自己遍历它 —— 代价 O(格数)。
func terrain_cells(id: StringName) -> PackedVector2Array:
	var arr: PackedVector2Array = _terrain_cells.get(id, PackedVector2Array())
	return arr

## 某个地形有多少格（调试 / 断言用）。
func terrain_cell_count(id: StringName) -> int:
	var arr: PackedVector2Array = _terrain_cells.get(id, PackedVector2Array())
	return arr.size()

# ---------------- 尸体层（用户拍板 2026-09-19） ----------------
## 尸体**永久留在格上**，但不算占格：活体可以从上面过。
## 移动决策"万不得已"才踩尸体格 —— 那是 GridMover 的规则，这里只存事实。

func place_corpse(c: Vector2i, who) -> void:
	var cell := grid.get_cell(c)
	if cell != null and cell.corpse == null:
		cell.corpse = who

func remove_corpse(c: Vector2i, who) -> void:
	var cell := grid.get_cell(c)
	if cell != null and cell.corpse == who:
		cell.corpse = null

func corpse_at(c: Vector2i):
	var cell := grid.get_cell(c)
	return cell.corpse if cell != null else null
