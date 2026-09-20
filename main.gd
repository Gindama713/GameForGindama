extends Node2D
## 主场景根节点。背景纯黑（project.godot 已设 default_clear_color 黑）。
## 网格逻辑在 GridManager（Autoload），时钟在 TimeSystem（Autoload）。
## 本文件是「组装根」：**生成地形 -> 放生物**，都走明确入口，不散落各处。

const PIG_SCENE := preload("res://creature/pig/pig.tscn")

## 两种地貌的"性质"（数量 / 落位 / 尺寸 / 形状 / 岸线怎么画）都在 .tres 里，本文件只负责接线。
## 本文件是**组装根**，也是唯一同时认识"草原"和"湖泊"的地方 —— 所以两个生成器
## 彼此不必认识（"谁贴谁、贴多远"由这里决定），这就是"降低耦合"的落点。
const GRASSLAND_DEF: GrasslandDef = preload("res://world/grassland/grassland_common.tres")
const LAKE_DEF: LakeDef = preload("res://world/lake/lake_common.tres")

## 世界种子统一来自 Autoload `WorldSeed`（草原/草场/生物 RNG 同源；不再在本文件写死）。
## 出生/落点用**种子化 RNG**（见 `_ready`）：原来走全局 `randf()/randi_range()`，
##   那些由引擎在每局启动时随机播种 -> **同一种子的开局落点每次不同**，
##   与"可复现"纪律相悖（事实文档里记了这条 [已知问题]，2026-09-20 修掉）。
const SPAWN_RNG_SALT := 0x5EED     # 与地形 RNG 区分开，避免"落点"和"地貌"抽到同一串数

## 猪落在**草原外围一圈黑地**（用户拍板："在草周围、不在草上"）：以草心为圆心，
## 内径 = 草原长半轴 + 1（贴着草边外沿），外径再 +SPAWN_RING_BAND 格，在这条环带里
## 随机挑 terrain==unknown 的空格出生。（环带用地图正中已看不到——相机不跟随，需平移去找。）
const SPAWN_RING_BAND := 12
## 家庭出生的方位**偏向"朝水那一侧"**：水在草原旁边，把家安在草与水之间，
## 两头都近（猪一次决策只走一格，通勤距离直接决定它活不活得下来）。
const SPAWN_BIAS_HALF := PI / 3.0

## 创始家庭数（用户拍板"一般草原旁边会有2-3个家庭"）。
## **按轮转分给各片草原** —— 不再全挤在一片草原上（世界有好几片草原）。
const FAMILY_MIN := 2
const FAMILY_MAX := 3

## 场上所有生物的容器节点（场景树里生物的「区」）。
## 【绘制顺序】它在 MapRenderer **之后** —— 兄弟节点按顺序绘制、后画的在上层，所以生物画在地表之上。
@onready var _creatures: Node2D = $Creatures

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSeed.value ^ SPAWN_RNG_SALT

	# 1) 先生成地形（草原 + 湖）：生物落格前地形必须已写好，否则隐蔽判定读到的是旧地形
	var stats: Dictionary = GrasslandGenerator.generate(GridManager.grid, WorldSeed.value, GRASSLAND_DEF)
	var g_centers: Array = stats["centers"]
	var g_reaches: Array = stats["reaches"]
	var g_majors: Array = stats["majors"]
	var n_grass: int = g_centers.size()

	# 1a) 湖：**每片草原旁边一片**（贴但留间隙）。把"每片草原占掉的圆区"作为**锚点**传进去 ——
	#     生成器不认识"草原"是什么，只知道"贴着这个圆放、边缘至少隔 anchor_gap"。
	var anchors: Array = []
	for i in n_grass:
		anchors.append(LakeGenerator.Anchor.new(Vector2(g_centers[i]), float(g_reaches[i])))
	var lake: Dictionary = LakeGenerator.generate(GridManager.grid, WorldSeed.value, LAKE_DEF, anchors)
	EventBus.terrain_changed.emit()      # 通知表现层（MapRenderer / Minimap）重画
	# 1a2) 岸线描述（ShoreSampler）+ 线宽/线色：渲染层只认这份数据，**不认生成器**
	EventBus.shorelines_changed.emit(lake["samplers"], LAKE_DEF.edge_width_px, LAKE_DEF.edge_color)
	# 1b) 草场播种：把刚画出的 grass/tall_grass 格建成"满耐久活草"，之后由 GrassField 自己推进再生/扩散
	GrassField.seed_existing(GridManager.grid)
	print("[草场] 播种活草 %d 格（成熟 %d 格）" % [GrassField.count(), GrassField.count_mature()])

	print("=== 网格就绪（逻辑层）===")
	print("尺寸: ", GridManager.grid.width, " x ", GridManager.grid.height, "  格宽: ", Grid.CELL_SIZE)
	print("世界像素: ", GridManager.grid.width * Grid.CELL_SIZE, " x ", GridManager.grid.height * Grid.CELL_SIZE)
	print("地形: 未知 %d 格 / 草原 %d 格 / 高草 %d 格 / 水域 %d 格（草原 %d 片 · 水 %d 片）" % [
		stats["unknown"], stats["grass"], stats["tall_grass"], lake["water"], n_grass, lake["count"]])
	print("坐标 (0,0) -> 世界位置 ", GridManager.grid.grid_to_world(Vector2i(0, 0)))
	print("坐标 (%d,0) 越界? %s" % [GridManager.WIDTH, not GridManager.in_bounds(GridManager.WIDTH, 0)])

	# 2) 每片草原"朝水"的方位：供出生把家庭安在草与水之间（哪片没配到水 -> 退化为绕一整圈）
	var lake_ang: Array[float] = []
	var has_lake: Array[bool] = []
	for i in n_grass:
		lake_ang.append(0.0)
		has_lake.append(false)
	var l_owner: Array = lake["anchor_index"]
	var l_centers: Array = lake["centers"]
	for i in l_centers.size():
		var ai: int = int(l_owner[i])
		if ai < 0 or ai >= n_grass or has_lake[ai]:
			continue                         # 只用第一片定方向（per_anchor > 1 时也一样）
		var d := Vector2(l_centers[i] - g_centers[ai])
		if d.length_squared() > 0.0001:
			has_lake[ai] = true
			lake_ang[ai] = d.angle()
	if lake["missed"] > 0:
		push_warning("[开局] 有 %d 片草原没配到水 —— 那片草原上的猪要走远路去找水" % int(lake["missed"]))

	# 3) 放猪：2~3 个家庭**轮转分给各片草原**（不挤在一处），每家分居该草原的一个扇区
	var n_fam := rng.randi_range(FAMILY_MIN, FAMILY_MAX)
	var start := rng.randi_range(0, maxi(n_grass - 1, 0))
	var per_grass: Array[int] = []
	per_grass.resize(n_grass)
	for f in n_fam:
		per_grass[(start + f) % n_grass] += 1
	var seq: Array[int] = []
	seq.resize(n_grass)
	for f in n_fam:
		var gi: int = (start + f) % n_grass
		var half := SPAWN_BIAS_HALF if has_lake[gi] else PI
		_spawn_family(g_centers[gi], int(ceil(float(g_majors[gi]))), seq[gi], per_grass[gi],
			lake_ang[gi], half, rng)
		seq[gi] += 1
	print("[开局] %d 个家庭 / 场上 %d 只生物（分居 %d 片草原旁），当前藏进高草 %d 只" % [
		n_fam, creature_count(), n_grass, concealed_count()])

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
func _pick_free_near(center: Vector2i, rmin: int, rmax: int, rng: RandomNumberGenerator) -> Vector2i:
	for _try in 200:
		var ang := rng.randf() * TAU
		var dist := rng.randi_range(rmin, rmax)
		var c := center + Vector2i(int(round(cos(ang) * dist)), int(round(sin(ang) * dist)))
		if not GridManager.in_bounds(c.x, c.y):
			continue
		var cell := GridManager.cell_at(c.x, c.y)
		if cell != null and cell.content == null and Terrain.walkable(cell.terrain):
			return c
	return Vector2i(-1, -1)

## 开局生成**一个家族**：父+母（成年）+ 一胎新生儿，登记亲缘。
## `sector/sectors`：这家落在草心的哪个**扇区**（同一片草原上的几家分居不同方位，不挤在一起）。
## `bias_ang/bias_half`：扇区围绕哪个方向展开 —— 传"朝水那一侧"就把家安在草与水之间（猪两头都近）。
func _spawn_family(center: Vector2i, grass_major: int, sector: int, sectors: int,
		bias_ang: float, bias_half: float, rng: RandomNumberGenerator) -> void:
	var ring_in := grass_major + 1
	var ring_out := grass_major + 1 + SPAWN_RING_BAND
	# 本家庭的锚点 = 草心 + 该扇区中线方向 × 环带中径
	var base_ang := bias_ang + (float(sector) + 0.5) / float(sectors) * (2.0 * bias_half) - bias_half
	var ring_mid := (ring_in + ring_out) * 0.5
	var anchor := center + Vector2i(int(round(cos(base_ang) * ring_mid)), int(round(sin(base_ang) * ring_mid)))
	# 父母（成年），落在锚点附近
	var f_at := _pick_free_near(anchor, 0, 4, rng)
	if f_at.x < 0:
		f_at = _pick_free_near(center, ring_in, ring_out, rng)
	if f_at.x < 0:
		return
	var father := _spawn_pig(f_at)
	if father == null:
		return
	var m_at := _free_adjacent(father.coord)
	if m_at.x < 0:
		m_at = _pick_free_near(anchor, 0, 4, rng)
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
	# 父母是**成年**：年龄 = 物种寿命 × 0.4（落在 LifeDef 的 mature_ratio 0.20 ~ elder_ratio 0.75 之间）。
	# 不设的话 Aging.setup 一律给 0 -> 全家都是幼崽（体型 25%、决策更慢、还全被 cling 绑在一起）。
	(father.get_component(Aging) as Aging).age_min = adult_age
	(mother.get_component(Aging) as Aging).age_min = adult_age
	# 孩子 = **真实一胎**：数量走 LifeDef.litter_min~litter_max（数据驱动，非硬编码），年龄=新生儿(0)
	var child_count := rng.randi_range(life.litter_min, life.litter_max) if life != null else 1
	for _i in child_count:
		var c_at := _pick_free_near(mother.coord, 1, 3, rng)
		if c_at.x < 0:
			c_at = _pick_free_near(center, ring_in, ring_out, rng)
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
