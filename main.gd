extends Node2D
## 主场景根节点。背景纯黑（project.godot 已设 default_clear_color 黑）。
## 网格逻辑在 GridManager（Autoload），时钟在 TimeSystem（Autoload）。
## 本文件是「组装根」：**生成地形 -> 放生物**，都走明确入口，不散落各处。

const PIG_SCENE := preload("res://creature/pig/pig.tscn")

## 世界种子统一来自 Autoload `WorldSeed`（草原/草场/生物 RNG 同源；不再在本文件写死）。

## 开局放几只猪
const SPAWN_COUNT := 12
## 猪落在**草原外围一圈黑地**（用户拍板："在草周围、不在草上"）：以草心为圆心，
## 内径 = 草原长半轴 + 1（贴着草边外沿），外径再 +SPAWN_RING_BAND 格，在这条环带里
## 随机挑 terrain==unknown 的空格出生。（环带用地图正中已看不到——相机不跟随，需平移去找。）
const SPAWN_RING_BAND := 12

## 草原旁的**创始家庭数**（用户拍板"一般草原旁边会有2-3个家庭"）；每家分居一个扇区。
const FAMILY_MIN := 2
const FAMILY_MAX := 3

## 场上所有生物的容器节点（场景树里生物的「区」）。
## 【绘制顺序】它在 MapRenderer **之后** —— 兄弟节点按顺序绘制、后画的在上层，所以生物画在地表之上。
@onready var _creatures: Node2D = $Creatures

func _ready() -> void:
	# 1) 先生成地形（草原）：生物落格前地形必须已写好，否则隐蔽判定读到的是旧地形
	var stats: Dictionary = GrasslandGenerator.generate(GridManager.grid, WorldSeed.value)
	EventBus.terrain_changed.emit()      # 通知表现层（MapRenderer / Minimap）重画
	# 1b) 草场播种：把刚画出的 grass/tall_grass 格建成"满耐久活草"，之后由 GrassField 自己推进再生/扩散
	GrassField.seed_existing(GridManager.grid)
	print("[草场] 播种活草 %d 格（成熟 %d 格）" % [GrassField.count(), GrassField.count_mature()])

	print("=== 网格就绪（逻辑层）===")
	print("尺寸: ", GridManager.grid.width, " x ", GridManager.grid.height, "  格宽: ", Grid.CELL_SIZE)
	print("世界像素: ", GridManager.grid.width * Grid.CELL_SIZE, " x ", GridManager.grid.height * Grid.CELL_SIZE)
	print("地形: 未知 %d 格 / 草原 %d 格 / 高草 %d 格" % [stats["unknown"], stats["grass"], stats["tall_grass"]])
	print("坐标 (0,0) -> 世界位置 ", GridManager.grid.grid_to_world(Vector2i(0, 0)))
	print("坐标 (%d,0) 越界? %s" % [GridManager.WIDTH, not GridManager.in_bounds(GridManager.WIDTH, 0)])

	# 2) 放猪：**草原旁 2~3 个家庭**（用户拍板），每家=父+母+一胎，分居草心不同扇区
	var grass_center: Vector2i = stats["center"]
	var grass_major: int = int(ceil(stats["major"]))
	var n_fam := randi_range(FAMILY_MIN, FAMILY_MAX)
	for i in n_fam:
		_spawn_family(grass_center, grass_major, i, n_fam)
	print("[开局] %d 个家庭 / 场上 %d 只生物（草心 @%s 外围），当前藏进高草 %d 只" % [n_fam, creature_count(), grass_center, concealed_count()])

	# 繁殖：Reproduction 只发请求，真造娃在这里（生成唯一入口，§3.2/§6.5）
	EventBus.birth_requested.connect(_on_birth_requested)

func _spawn_pig(at: Vector2i) -> Creature:
	var pig: Creature = PIG_SCENE.instantiate()
	pig.coord = at            # 必须在 add_child 前设好，_ready 才会落对格
	_creatures.add_child(pig)
	# 定义校验没过 / 坐标不可用 -> Creature 会拒绝生成（queue_free）。
	# 这时不能把失效引用交出去，否则调用方一碰就 "previously freed"。
	if pig.is_queued_for_deletion():
		return null
	EventBus.creature_spawned.emit(pig)   # 表现层（小地图等）订阅；生成即广播
	return pig

## 繁殖请求入口：Reproduction 判定"可育母+相邻可育公+营养+冷却"后发信号，这里执行。
func _on_birth_requested(mother: Node, father: Node) -> void:
	var m := mother as Creature
	var f := father as Creature
	if m == null or f == null:
		return
	_spawn_offspring(m, f)

## 真造娃：落母亲相邻空格 + 登记双亲 + 遗传（性格/寿命）。
func _spawn_offspring(mother: Creature, father: Creature) -> void:
	# 种群软上限（防指数爆炸）
	var life: LifeDef = mother.def.life if mother.def != null else null
	if life != null and FamilyRegistry.living_count() >= life.max_population:
		return
	var at := _free_adjacent(mother.coord)
	if at.x < 0:
		return
	var child := _spawn_pig(at)
	if child == null:
		return
	# 亲缘登记
	var cl: Lineage = child.get_component(Lineage) as Lineage
	var ml: Lineage = mother.get_component(Lineage) as Lineage
	var fl: Lineage = father.get_component(Lineage) as Lineage
	if cl != null:
		if ml != null:
			cl.mother_id = mother.id
			ml.add_child_id(child.id)
		if fl != null:
			cl.father_id = father.id
			fl.add_child_id(child.id)
	# 遗传：性格 = 父母均值±抖动；寿命 = 父母均值×个体方差
	var cp: Personality = child.get_component(Personality) as Personality
	var mp: Personality = mother.get_component(Personality) as Personality
	var fp: Personality = father.get_component(Personality) as Personality
	if cp != null:
		cp.inherit(mp, fp)
	var ca: Aging = child.get_component(Aging) as Aging
	var ma: Aging = mother.get_component(Aging) as Aging
	var fa: Aging = father.get_component(Aging) as Aging
	if ca != null and ma != null and fa != null and life != null:
		var mean_life := (ma.lifespan_min + fa.lifespan_min) * 0.5
		ca.lifespan_min = mean_life * child.rng.randf_range(1.0 - life.variance, 1.0 + life.variance)
	Log.ev("生成", "%s 出生（母#%d 父#%d）@%s" % [child.tag(), mother.id, father.id, at])

## 母亲周围找一个空且可踩的格（8 邻域）；没有返回 (-1,-1)。
func _free_adjacent(center: Vector2i) -> Vector2i:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := center + Vector2i(dx, dy)
			if not GridManager.in_bounds(c.x, c.y):
				continue
			var cell := GridManager.cell_at(c.x, c.y)
			if cell != null and cell.content == null and Terrain.walkable(cell.terrain):
				return c
	return Vector2i(-1, -1)

## 在 center 周围 [rmin, rmax] 环带挑一个空且可踩的格；失败返回 (-1,-1)。
func _pick_free_near(center: Vector2i, rmin: int, rmax: int) -> Vector2i:
	for _try in 200:
		var ang := randf() * TAU
		var dist := randi_range(rmin, rmax)
		var c := center + Vector2i(int(round(cos(ang) * dist)), int(round(sin(ang) * dist)))
		if not GridManager.in_bounds(c.x, c.y):
			continue
		var cell := GridManager.cell_at(c.x, c.y)
		if cell != null and cell.content == null and Terrain.walkable(cell.terrain):
			return c
	return Vector2i(-1, -1)

## 开局生成**一个家族**：父+母（成年）+ 一胎新生儿，登记亲缘。
## sector/sectors 决定这家落在草心的哪个**扇区**（2~3 家分居不同方位，不挤在一起）。
func _spawn_family(center: Vector2i, grass_major: int, sector: int, sectors: int) -> void:
	var ring_in := grass_major + 1
	var ring_out := grass_major + 1 + SPAWN_RING_BAND
	# 本家庭的锚点 = 草心 + 该扇区中线方向 × 环带中径
	var base_ang := (float(sector) + 0.5) / float(sectors) * TAU
	var ring_mid := (ring_in + ring_out) * 0.5
	var anchor := center + Vector2i(int(round(cos(base_ang) * ring_mid)), int(round(sin(base_ang) * ring_mid)))
	# 父母（成年），落在锚点附近
	var f_at := _pick_free_near(anchor, 0, 4)
	if f_at.x < 0:
		f_at = _pick_free_near(center, ring_in, ring_out)
	if f_at.x < 0:
		return
	var father := _spawn_pig(f_at)
	if father == null:
		return
	var m_at := _free_adjacent(father.coord)
	if m_at.x < 0:
		m_at = _pick_free_near(anchor, 0, 4)
	if m_at.x < 0:
		return
	var mother := _spawn_pig(m_at)
	if mother == null:
		return
	var life: LifeDef = father.def.life
	var adult_age := life.lifespan_min * 0.4 if life != null else 0.0
	var fl: Lineage = father.get_component(Lineage) as Lineage
	var ml: Lineage = mother.get_component(Lineage) as Lineage
	fl.sex = Lineage.Sex.MALE
	ml.sex = Lineage.Sex.FEMALE
	(father.get_component(Aging) as Aging).age_min = adult_age
	(mother.get_component(Aging) as Aging).age_min = adult_age
	# 孩子 = **真实一胎**：数量走 LifeDef.litter_min~litter_max（数据驱动，非硬编码），年龄=新生儿(0)
	var child_count := randi_range(life.litter_min, life.litter_max) if life != null else 1
	for _i in child_count:
		var c_at := _pick_free_near(mother.coord, 1, 3)
		if c_at.x < 0:
			c_at = _pick_free_near(center, ring_in, ring_out)
		if c_at.x < 0:
			continue
		var child := _spawn_pig(c_at)
		if child == null:
			continue
		var cl: Lineage = child.get_component(Lineage) as Lineage
		cl.mother_id = mother.id
		cl.father_id = father.id
		ml.add_child_id(child.id)
		fl.add_child_id(child.id)
		# 新生儿 age=0（Aging 默认），不 artificially 设年龄 → 族谱上"多大就是多大"

## 在**草原外围的环带**（黑地）挑空格放一只猪：绕草心随机角度 + 距离 ∈ [inner, outer]，
## 只落在 `terrain == unknown`（草原外）且没被占的格 —— 即"在草周围、不在草上"（用户拍板）。
## 这里只**读** cell 判断；真正占格仍走 Creature -> GridManager.occupy（唯一入口）。
func spawn_pig_around_grass(center: Vector2i, inner: int, outer: int) -> void:
	for _try in 300:
		var ang := randf() * TAU
		var dist := randi_range(inner, outer)
		var x := center.x + int(round(cos(ang) * dist))
		var y := center.y + int(round(sin(ang) * dist))
		var cell := GridManager.cell_at(x, y)
		if cell != null and cell.content == null and cell.terrain == Terrain.UNKNOWN:
			_spawn_pig(Vector2i(x, y))
			return
	Log.ev("调试", "草原外围没有合适空格，本次少放一只猪")

## 调试工具栏「刷猪」用：全图随机空格生成一只猪（O(1)，GridManager 维护空格集合）
func spawn_pig_random() -> void:
	var c := GridManager.random_free_cell()
	if c.x < 0:
		print("没有空格可以刷猪了")
		return
	_spawn_pig(c)

## 场上隐蔽中的生物数（自检/调试用）
func concealed_count() -> int:
	var n := 0
	for c in _creatures.get_children():
		if c is Creature and (c as Creature).is_concealed():
			n += 1
	return n

## 清空场上所有生物（调试用）。**唯一入口** —— 工具栏不自己遍历节点树，
## 因为「生物装在哪个节点下」是 Main 的知识，不是工具栏的知识。
func clear_creatures() -> int:
	var removed := 0
	for c in _creatures.get_children():
		EventBus.creature_removed.emit(c)
		c.queue_free()
		removed += 1
	if removed > 0:
		Log.ev("调试", "清屏：移除 %d 只生物" % removed)
	return removed

## 场上生物数量（调试/自检用）
func creature_count() -> int:
	return _creatures.get_child_count()
