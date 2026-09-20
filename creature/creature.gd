class_name Creature
extends Node2D

## 生物基类 —— 只放 100% 通用的东西：
##   我是谁(def) / 我在哪格(coord) / 我还活着吗(_alive) / 组件表 / 每帧 tick / 占格。
## 具体的能力与需求（移动、游荡、饥饿、家的位置…）全在组件里，由 CreatureDef 声明式挂载。
##
## 【纪律 1】基类**只认组件协议，不认识任何具体组件**。
##   想在这里写 get_component(Body) 之类的代码，说明该做的事应该做成组件钩子。
## 【纪律 2】`_alive` 是私有字段：外部只读 `is_alive()`，**唯一改变它的是 `die()`**。
## 【纪律 3】初始化不通过就**拒绝生成**（queue_free），绝不半死不活地占着格子。

@export var def: CreatureDef
var coord: Vector2i = Vector2i.ZERO
var _alive: bool = true          # 唯一事实来源 —— 全项目只有 die() 能把它变成 false

static var _next_id: int = 1     # 全局自增编号（日志里好认）
var id: int = 0

## 个体随机源。用它代替全局 randf_range/randi —— 同一颗种子能复现整场模拟，
## 这是存档/回放能对上的前提。存档直接存 rng.seed 即可复现。
var rng := RandomNumberGenerator.new()
static var _seed_offset: int = 0

var _components: Dictionary = {}   # 脚本路径(String) -> 组件实例
var _sprite: Sprite2D

## 速度总倍率的硬上限（见 `current_speed()`）。疾跑 = 2.0，留一倍余量给将来
##   （骑乘 / 下坡 / 药物）—— 但**必须有个顶**，否则某天一个乘法写错就把生物瞬移了。
const SPRINT_SPEED_MAX := 4.0

func _ready() -> void:
	id = _next_id
	_next_id += 1
	rng.seed = WorldSeed.value + _seed_offset
	_seed_offset += 1
	FamilyRegistry.register(self)      # 家族注册表：让 Lineage 的 id 能解析到活体

	if def == null:
		_fail_init("未设置 def")
		return
	var problems := def.validate()
	if not problems.is_empty():
		for p in problems:
			push_error("[%s] 定义有问题：%s" % [tag(), p])
		_fail_init("定义校验未通过（%d 项）" % problems.size())
		return
	if not can_place_at(coord):
		_fail_init("初始坐标 %s 越界或已被占" % coord)
		return

	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_build_components()
	_render()
	_place_at(coord)
	_apply_appearance()                 # 生成时就可能站在高草里 -> 立刻应用"看不见"
	TimeSystem.tick.connect(_on_tick)   # 时间统一来自 TimeSystem；对象释放后连接自动断
	_log_spawn()

## 初始化失败 → 明确拒绝生成。宁可什么都不生成，也不要一个占着格子、还在 tick 的幽灵实体。
func _fail_init(reason: String) -> void:
	push_error("[%s] 初始化失败：%s —— 拒绝生成（不占格、不接时钟）" % [tag(), reason])
	set_process(false)
	set_physics_process(false)
	queue_free()

## 还活着吗（外部只读入口）
func is_alive() -> bool:
	return _alive

## 宿主当前是否被地形藏起来（如站在高草丛里）。
## 与 is_dead_state() 同构：基类只**汇总**各组件的事实，不认识 Concealment 这个具体组件。
func is_concealed() -> bool:
	for comp in _components.values():
		if comp.is_concealed():
			return true
	return false

## 显示名（带编号），日志用
func tag() -> String:
	var n: String = String(name)
	if def != null:
		n = def.display_name
	return "%s#%d" % [n, id]

## 生成时把「属性」全部打到终端，方便调试。
## 各组件自己提供 debug_state()，本函数只做拼接 —— 加新组件不必来这里改代码。
func _log_spawn() -> void:
	var comp_names: Array[String] = []
	var frags: Array[String] = []
	for key in _components.keys():
		var comp: CreatureComponent = _components[key]
		comp_names.append(String(key).get_file().get_basename())
		var frag: String = comp.debug_state()
		if not frag.is_empty():
			frags.append(frag)
	var s := "%s @%s 组件[%s]" % [tag(), coord, ", ".join(comp_names)]
	if not frags.is_empty():
		s += " " + " ".join(frags)
	Log.ev("生成", s)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		FamilyRegistry.unregister(self)   # 死/清屏后从家族表摘除 → 亲缘解析为 null（"已故"）
		_release_cell()
		GridManager.remove_corpse(coord, self)   # 尸体节点被清（清屏）时把格子上的尸体也撤走

# ---------------- 点击选取 ----------------
## 用 _unhandled_input 而非 _input：被 UI 消费掉的点击（面板/按钮）不会到达这里，
## 因此点检视窗不会「穿透」选中窗下的生物。
## 活体优先：尸体格上站着活体时，点击选中活体；尸体只在格上没有活体时才可被点（验尸）。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var vp := get_viewport()
		var world_pos: Vector2 = vp.get_canvas_transform().affine_inverse() * event.position
		if GridManager.grid.world_to_grid(world_pos) != coord:
			return
		if _alive:
			EventBus.creature_clicked.emit(self)
			vp.set_input_as_handled()
			return
		var cell := GridManager.cell_at(coord.x, coord.y)
		if cell != null and cell.content is Creature and (cell.content as Creature).is_alive():
			return                              # 活体踩在身上：让活体响应，尸体不打架
		EventBus.creature_clicked.emit(self)    # 尸体独占格 → 可点击验尸
		vp.set_input_as_handled()

# ---------------- 组件装配（组合，而非继承） ----------------
func _build_components() -> void:
	_components.clear()
	for s in def.component_scripts:
		var comp: CreatureComponent = s.new()
		comp.setup(self)
		_components[s.resource_path] = comp

func get_component(script: Script) -> CreatureComponent:
	return _components.get(script.resource_path)

func has_component(script: Script) -> bool:
	return _components.has(script.resource_path)

## 全部组件实例（组件间协作 / 基类遍历协议用）
func get_components() -> Array:
	return _components.values()

# ---------------- 调试可见性：把组件状态暴露成只读属性 ----------------
## 痛点：组件是 RefCounted，**不在场景树里**，运行时在调试器的场景树中根本看不到它们
## ——「生物在动，但不知道它内部怎么了」。
##
## 解法不是把组件改成节点：那要给每只生物 +4 个节点，1500 只就是 6000 个；
## 官方《Node alternatives》明确说「不需要进场景树的东西用 RefCounted/Resource」。
## 改成**只读合成属性**：运行中在调试器里选中一只生物，检查器就能实时看到
## 编号 / 坐标 / 生死 / 每个组件自述的状态（组件照旧只提供 debug_state()，基类不认识它们）。
func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append(_debug_prop("debug/id", TYPE_INT))
	props.append(_debug_prop("debug/coord", TYPE_VECTOR2I))
	props.append(_debug_prop("debug/alive", TYPE_BOOL))
	props.append(_debug_prop("debug/tag", TYPE_STRING))
	for key in _components.keys():
		props.append(_debug_prop("debug/components/" + String(key).get_file().get_basename(), TYPE_STRING))
	return props

## 只读合成属性：EDITOR 让它出现在检查器里，READ_ONLY 让它不可改（不写 STORAGE → 不会被存进 .tscn）
func _debug_prop(name: String, type: int) -> Dictionary:
	return {
		"name": name,
		"type": type,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
	}

## 合成属性的取值入口：这些名字不是真实字段，Godot 找不到就会转到这里问。
func _get(property: StringName) -> Variant:
	var p := String(property)
	match p:
		"debug/id":
			return id
		"debug/coord":
			return coord
		"debug/alive":
			return _alive
		"debug/tag":
			return tag()
	if p.begins_with("debug/components/"):
		var label := p.trim_prefix("debug/components/")
		for key in _components.keys():
			if String(key).get_file().get_basename() == label:
				return (_components[key] as CreatureComponent).debug_state()
	return null

const DEAD_COLOR := Color(0.32, 0.32, 0.32)

# ---------------- 生死：判定 / 接线 / 执行 ----------------
## 结构照搬 CDDA（src/creature.h）：
##   is_dead_state()    —— 判定：问所有组件「我算不算死了」
##   check_dead_state() —— 接线：基类唯一负责 if(is_dead_state()) die()
##   die()              —— 执行：只做一次的状态迁移
## 组件永远不调 die()，只重写 is_lethal() 报告事实。
## 于是「加一种死法」既不用碰 die()，也不用在 tick 循环里补判断。

## 宿主是否已到死境：问所有组件，任一为真即真。加死法 = 加组件，本函数不动。
func is_dead_state() -> bool:
	for comp in _components.values():
		if comp.is_lethal():
			return true
	return false

## 死因说明（取第一个报告死境的组件给的描述），用于死亡日志。
func lethal_reason_text() -> String:
	for comp in _components.values():
		if comp.is_lethal():
			var why: String = comp.lethal_reason()
			if not why.is_empty():
				return why
	return ""

## 死亡执行入口 —— 全项目唯一改变 _alive 的地方。
## 正常由 check_dead_state() 调用；调试工具可以直接调。
func die() -> void:
	if not _alive:
		return                                  # 幂等：多个要害同时归零也只死一次
	var why := lethal_reason_text()
	_alive = false
	TimeSystem.tick.disconnect(_on_tick)        # 停机机制：把自己从时钟上摘下来
	_release_cell()                             # 交还占格：活体可以从这格过
	GridManager.place_corpse(coord, self)       # 尸体**永久留在格上**（不占格，但移动"万不得已"才踩）
	if _sprite != null and def != null and def.texture != null:
		_sprite.modulate = DEAD_COLOR            # 有图：调暗
	queue_redraw()                              # 无图：色块由 _draw 自己变暗
	var suffix := "" if why.is_empty() else "（%s）" % why
	Log.ev("死亡", "%s%s 死亡 @%s，模拟停止" % [tag(), suffix, coord])
	EventBus.creature_died.emit(self)

## 每帧 tick 末尾的统一接线：全项目只有这里会「问一次生死」。谁都不必记得自己查。
func check_dead_state() -> void:
	if not _alive:
		return
	if is_dead_state():
		die()

func _on_tick(dt: float) -> void:
	for comp in _components.values():
		comp.tick(dt)
	_refresh_growth_scale()
	check_dead_state()

# ---------------- 网格占位 ----------------
## 该格能否被我占：在界内 + **地形可踩** + 是空格或是自己。
##
## 【为什么要查地形（2026-09-20 补）】原先只查界内和占格，于是"能不能站"与"能不能走过去"
##   是两套规则 —— `GridMover` 走一步要 `Terrain.walkable()`，而落格不需要。
##   现在没有东西会主动把自己放进水里，**但规则不对称就是雷**：
##   将来任何一个"把 X 放到空格上"的工具（落物 / 传送 / 繁殖找空位）都会直接踩进去。
##   补上这一条，让**"能落格"成为"能移动"的真子集** —— 同一事实只有一处定义。
##   `self.is_terrain_ok()` 见下方；`unknown`（黑土）与 `grass` 都是 walkable，不受影响。
func can_place_at(c: Vector2i) -> bool:
	if not GridManager.in_bounds(c.x, c.y):
		return false
	var cell := GridManager.cell_at(c.x, c.y)
	if cell == null:
		return false
	if not Terrain.walkable(cell.terrain):
		return false
	return cell.content == null or cell.content == self

## 写入占格。**占格唯一入口 = GridManager.occupy()**（同时维护空格集合）。
func _place_at(c: Vector2i) -> bool:
	var cell := GridManager.cell_at(c.x, c.y)
	if cell == null:
		push_error("[%s] %s 越界，未占格" % [tag(), c])
		return false
	if not GridManager.occupy(c, self):
		push_error("[%s] %s 已被 %s 占用，未抢占" % [tag(), c, cell.content])
		return false
	# grid_to_world 返回格子左上角，加半格才居中
	position = GridManager.grid.grid_to_world(c) + Vector2(Grid.CELL_SIZE, Grid.CELL_SIZE) * 0.5
	return true

## 交还所占格子（死亡 / 释放时）。释放唯一入口 = GridManager.release()。
func _release_cell() -> void:
	GridManager.release(coord, self)

## 移动到相邻格（由移动组件调用）。成功返回 true。
## 越界或目标被占 → 报错并原地不动（不会留下 coord 与占格不一致的状态）。
func move_to(target: Vector2i) -> bool:
	if not can_place_at(target):
		push_error("[%s] 无法移动到 %s（越界或被占），已忽略" % [tag(), target])
		return false
	Log.ev("移动", "%s %s → %s" % [tag(), coord, target])
	_release_cell()
	coord = target
	var ok := _place_at(target)
	if ok:
		_apply_appearance()                  # 换了格子 -> 地形可能不同 -> 重新判定隐蔽
		EventBus.creature_moved.emit(self)   # 小地图等表现层重画；将来脚印/噪音也听它
	return ok

# ---------------- 表现（可选，删掉不影响逻辑） ----------------
## 主画面：**有图就用图**（猪 = pic/pig.png 剪影，缩放成一格）；
## 没配 texture 的物种才用 `map_color` 色块兜底 —— 保证"不配图也能被看见"。
## 小地图（Minimap）不看图，一律用 `def.map_color` 的色点。
const BODY_SIZE := 20.0   # 兜底色块边长（格子 32px，留边显"棋子"感）

## 依据「是否隐蔽」刷新表现。隐蔽 = **完全看不见**（用户拍板 2026-09-19）：
##   有图 -> 隐藏 Sprite2D；无图 -> _draw() 提前 return 不画兜底色块。
## 只在「生成」与「移动」两个时机调用 —— 地形只在移动时变，不必每帧重算。
func _apply_appearance() -> void:
	var hidden := is_concealed()
	if _sprite != null:
		_sprite.visible = not hidden
	queue_redraw()

func _render() -> void:
	if _sprite == null or def == null or def.texture == null:
		queue_redraw()          # 走 _draw 的色块兜底
		return
	_sprite.texture = def.texture
	var k := float(Grid.CELL_SIZE) / float(def.texture.get_width())
	_sprite.scale = Vector2(k, k) * _aggregate_scale()
	_apply_injury_tint()

## 按伤势给精灵染色（协议 7 聚合）。**死后不覆盖** —— 死亡色调是更重的终态。
func _apply_injury_tint() -> void:
	if _sprite == null or not _alive:
		return
	_sprite.self_modulate = _aggregate_tint()

## 各组件 visual_scale 相乘（协议聚合，基类不认识具体组件；默认全 1.0 → 不变）。
func _aggregate_scale() -> float:
	var s := 1.0
	for comp in _components.values():
		s *= comp.visual_scale()
	return s

## 各组件 injury_tint 取**离白最远**的一个（协议聚合，基类不认识具体组件）。
##
## ⚠ 与 _aggregate_scale() 的规则**不同**：缩放相乘、染色取最重。
##   颜色相乘会越乘越黑（黄×红=暗橙），语义就丢了 —— "受伤"是**取最严重的一个**，不是叠加。
## 默认全白 → 返回白 → 不给精灵染色（不改变原有外观）。
func _aggregate_tint() -> Color:
	var best := Color(1, 1, 1, 1)
	var best_d := 0.0
	for comp in _components.values():
		# ⚠ `comp` 从 Dictionary 取出是 Variant → `:=` 推不出返回类型（坑 7）。
		var c: Color = comp.injury_tint()
		# 偏离度 = 离白色多远（1 - 最接近白的那个通道）。纯白 = 0。
		var d := 1.0 - minf(minf(c.r, c.g), c.b)
		if d > best_d:
			best_d = d
			best = c
	return best

## 宿主当前的移动速度系数（0..1；1 = 满速，0 = 动不了）。
##
## 与 is_concealed() / _aggregate_scale() 同构：**基类只做乘积聚合，不认识任何具体组件**。
## 于是「腿断了 / 累极了 / 老幼」这些减速来源各自在自己的组件里实现 `move_speed_factor()`，
## 想加一种新减速（负重超限 / 中毒 / 雪地）也不必回来改这里。
##
## ⚠ 与 `GridMover.can_move()` 的分工：
##   can_move()   —— 「**能不能**动」（协议 2 allows_movement，全票才放行的硬否决）
##   locomotion_speed() —— 「动得**多快**」（协议 6，连续量，喂给 PlayerBrain 的步频 gate）
## 两者独立：全断腿时被前者否决，走了也没用；而"瘸了一条腿"是前者放行、后者减速。
##
## 【2026-09-20 加疾跑：两个槽分开乘】见 `current_speed()` —— 本函数仍只管**减益**
##   （语义没变，仍是钳 0..1），疾跑走协议 6b 的独立槽。
func locomotion_speed() -> float:
	var s := 1.0
	for comp in _components.values():
		s *= comp.move_speed_factor()
	return clampf(s, 0.0, 1.0)

## 宿主**实际**的移动速度系数（含疾跑增益）。
##
## 【为什么要有这一层】`locomotion_speed()` 的语义是"减益聚合"（钳 0..1），
##   而疾跑要 > 1 —— 如果直接放宽它的钳制，减益与增益就混进同一个槽，
##   一条失控的减益也能把速度推过 1.0，边界失效。
##   于是：**减益走协议 6（钳 0..1）、增益走协议 6b（钳 1..SPRINT_MAX），
##   两条轴各自钳好再相乘** —— 谁也污染不了谁。
##
## 【谁该调哪个】
##   大脑（PlayerBrain / Brain）**一律调本函数**去算步频 gate —— 它才是"这人现在多快"。
##   `locomotion_speed()` 保留给"只看身体状态不看是否在跑"的场合（如调试自述、平衡回归）。
func current_speed() -> float:
	var slow := locomotion_speed()          # 协议 6：减益，已钳 0..1
	var fast := 1.0
	for comp in _components.values():
		fast *= comp.sprint_speed_factor()
	fast = clampf(fast, 1.0, SPRINT_SPEED_MAX)   # 协议 6b：增益，钳 1..上限
	return clampf(slow * fast, 0.0, SPRINT_SPEED_MAX)

## 成长是连续的：每 tick 轻量刷新一次精灵缩放（只在有图时；一次乘法+赋值，很便宜）。
## **顺带刷新伤势染色** —— 伤是随时可能挨的（不必等移动才更新外观），
## 两个都是"每 tick 一次赋值"级别的开销，合在一起省一次遍历。
func _refresh_growth_scale() -> void:
	if _sprite == null or def == null or def.texture == null:
		return
	var k := float(Grid.CELL_SIZE) / float(def.texture.get_width())
	_sprite.scale = Vector2(k, k) * _aggregate_scale()
	_apply_injury_tint()

func _draw() -> void:
	if is_concealed():
		return                  # 藏进高草：连兜底色块也不画（完全看不见）
	if def == null or (_sprite != null and def.texture != null):
		return                  # 有图在显示，不画兜底块
	var col: Color = def.map_color if _alive else DEAD_COLOR
	# 无图物种也按伤势染色（与有图物种同一套协议，只是改的是兜底块的颜色）
	if _alive:
		col = col * _aggregate_tint()
	draw_rect(Rect2(Vector2.ONE * -BODY_SIZE * 0.5, Vector2.ONE * BODY_SIZE), col)
