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
static var _world_seed: int = 20260918
static var _seed_offset: int = 0

var _components: Dictionary = {}   # 脚本路径(String) -> 组件实例
var _sprite: Sprite2D

func _ready() -> void:
	id = _next_id
	_next_id += 1
	rng.seed = _world_seed + _seed_offset
	_seed_offset += 1

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
		_release_cell()

# ---------------- 点击选取 ----------------
## 用 _unhandled_input 而非 _input：被 UI 消费掉的点击（面板/按钮）不会到达这里，
## 因此点检视窗不会「穿透」选中窗下的生物。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var vp := get_viewport()
		var world_pos: Vector2 = vp.get_canvas_transform().affine_inverse() * event.position
		if GridManager.grid.world_to_grid(world_pos) == coord:
			EventBus.creature_clicked.emit(self)
			vp.set_input_as_handled()   # 一次点击只选一个，避免重叠时全部触发

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
	_release_cell()                             # 尸体不再占格（否则是看不见的堵路石）
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
	check_dead_state()

# ---------------- 网格占位 ----------------
## 该格能否被我占：在界内 + 是空格或是自己。
func can_place_at(c: Vector2i) -> bool:
	if not GridManager.in_bounds(c.x, c.y):
		return false
	var cell := GridManager.cell_at(c.x, c.y)
	if cell == null:
		return false
	return cell.content == null or cell.content == self

## 写入占位。调用前必须已通过 can_place_at()（本函数仍会复核并报错，不静默抢占）。
func _place_at(c: Vector2i) -> bool:
	var cell := GridManager.cell_at(c.x, c.y)
	if cell == null:
		push_error("[%s] %s 越界，未占格" % [tag(), c])
		return false
	if cell.content != null and cell.content != self:
		push_error("[%s] %s 已被 %s 占用，未抢占" % [tag(), c, cell.content])
		return false
	cell.content = self
	# grid_to_world 返回格子左上角，加半格才居中
	position = GridManager.grid.grid_to_world(c) + Vector2(Grid.CELL_SIZE, Grid.CELL_SIZE) * 0.5
	return true

## 交还所占格子（死亡 / 释放时）
func _release_cell() -> void:
	var cell := GridManager.cell_at(coord.x, coord.y)
	if cell != null and cell.content == self:
		cell.content = null

## 移动到相邻格（由移动组件调用）。成功返回 true。
## 越界或目标被占 → 报错并原地不动（不会留下 coord 与占格不一致的状态）。
func move_to(target: Vector2i) -> bool:
	if not can_place_at(target):
		push_error("[%s] 无法移动到 %s（越界或被占），已忽略" % [tag(), target])
		return false
	Log.ev("移动", "%s %s → %s" % [tag(), coord, target])
	_release_cell()
	coord = target
	return _place_at(target)

# ---------------- 表现（可选，删掉不影响逻辑） ----------------
## 主画面：**有图就用图**（猪 = pic/pig.png 剪影，缩放成一格）；
## 没配 texture 的物种才用 `map_color` 色块兜底 —— 保证"不配图也能被看见"。
## 小地图（Minimap）不看图，一律用 `def.map_color` 的色点。
const BODY_SIZE := 20.0   # 兜底色块边长（格子 32px，留边显"棋子"感）

func _render() -> void:
	if _sprite == null or def == null or def.texture == null:
		queue_redraw()          # 走 _draw 的色块兜底
		return
	_sprite.texture = def.texture
	var k := float(Grid.CELL_SIZE) / float(def.texture.get_width())
	_sprite.scale = Vector2(k, k)

func _draw() -> void:
	if def == null or (_sprite != null and def.texture != null):
		return                  # 有图在显示，不画兜底块
	var col: Color = def.map_color if _alive else DEAD_COLOR
	draw_rect(Rect2(Vector2.ONE * -BODY_SIZE * 0.5, Vector2.ONE * BODY_SIZE), col)
