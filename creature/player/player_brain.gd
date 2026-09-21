class_name PlayerBrain
extends CreatureComponent

## 玩家大脑（2026-09-20）—— 顶替 `Brain` 的位置：**同样"决定下一步做什么"，但决策来源是键盘**。
##
## 【为什么组件里能直接读 Input】组件是 RefCounted、拿不到 `_input` 回调；
##   但 `Input` 是**全局单例**，组件里可直接轮询（`Input.get_vector`）。
##   于是**不需要把输入路由进 `Creature`** —— 基类照旧不认识任何具体组件。
##
## 【职责边界 —— 与 Brain 完全对齐】
##   本组件只管「**往哪走、什么时候走**」；「能不能走 / 走过去」交 `GridMover.try_step()`。
##   所以：越界、目标被占、**腿全断（Body 否决）** 全都自动拦下，本组件一行不用写。
##
## 【步频随身体状态变（决策1 的核心）】
##   gate = `def.move_interval / current_speed()`
##   满状态 ≈ 0.8s/格；累了/断腿/老幼 → gate 变长 → 明显走得慢；腿全断 → 走不动。
##   含**疾跑**：按住 Shift 时 `Sprint` 走协议 6b 给一个 ×2 → gate 直接减半
##   （速度翻倍 = 每格耗时减半），**本文件不需要知道疾跑的内部**。
##   `current_speed()` 是**基类聚合各组件协议得来的**（基类不认识 Body/Needs/Aging/Sprint），
##   所以本组件也**不点名任何减速/加速来源**。
##
## 【意图先过 PlayerIntent】行走请求一律 `submit → apply → 执行`，
##   将来「痛/慌/累夺走控制」插在 `PlayerIntent.apply()`，不动本文件主干。

## true = 按住方向键连续走（决策1 定稿）；false = 按一次走一格（回合感，留作可切换）。
const HOLD_MOVE := true

## 速度下限保护：current_speed 可能很小（幼崽+断半腿+累 ≈ 0.17），
## 直接除会得到极长的 gate。钳一个下限，保证"再慢也还是会挪"，而不是变成静止。
## 真"不能动"由 `GridMover.can_move()`（协议 2）否决，不靠这里。
const MIN_SPEED := 0.15

## 疾跑输入动作名（`project.godot`）
const ACTION_SPRINT := "sprint"

## 睡眠输入动作名（`project.godot`，KEY_R）。
## 【为什么用**自己做的边沿检测**而不是 `Input.is_action_just_pressed()`】
##   本组件的 `tick()` 挂在 `TimeSystem.tick` 上（= `_physics_process`），
##   而"刚刚按下"这种边沿量在"渲染帧率 ≠ 物理帧率"时容易漏掉或重复触发。
##   自己记住上一帧的按键状态最稳，而且与下面 `_prev` 的方向边沿检测是同一套写法。
const ACTION_SLEEP := "sleep"

## 4 向映射用的方向名（调试自述）
const DIR_NAMES := {
	Vector2i.UP: "上", Vector2i.DOWN: "下", Vector2i.LEFT: "左", Vector2i.RIGHT: "右",
}

var _step_acc: float = 0.0          # 距上一次迈步攒了多久（游戏分钟）
var _prev: Vector2i = Vector2i.ZERO  # 上一次读到的输入方向（HOLD_MOVE=false 时的边沿检测用）
var _sleep_key_prev := false         # 上一帧睡眠键是否按下（自己做的边沿检测，见 ACTION_SLEEP）
var _intent := PlayerIntent.new()    # 意图 + 干扰层挂点（v1 直通）

func requires() -> Array:
	return [GridMover]               # 硬依赖：没有移动组件就无从行动（与 Brain 同）

func setup(host: Node) -> void:
	super.setup(host)
	_step_acc = 0.0
	_prev = Vector2i.ZERO
	_sleep_key_prev = false

func tick(dt: float) -> void:
	# 不判断生死 —— 死了就不会被 tick（Creature.die() 已把宿主摘出时钟）

	# —— 睡眠开关（2026-09-21）：按一下躺下，再按一下叫醒自己 ——
	# 【为什么是"切换"而不是"按住"】睡一夜在加速下是十几秒，按住 R 十几秒很难受；
	#   而且"想醒就醒"本来就是一个独立动作，不是"松手"。
	var sl := creature.get_component(Sleep) as Sleep
	var key_down := Input.is_action_pressed(ACTION_SLEEP)
	if key_down and not _sleep_key_prev and sl != null:
		if sl.is_sleeping():
			sl.wake_up("自己按醒了")
		elif not sl.start():
			# 被拒的原因只有一个：还不困（疲劳 ≥ `Sleep.WAKE_FATIGUE_RATIO`）。
			# 【为什么日志打在这里、不打在 `Sleep` 里】组件只回答"能不能睡"，
			#   "要不要告诉玩家"是调用方的事 —— `Brain` 的 rest 驱动每秒都会试一次，
			#   日志写在组件里会让一只疲劳满的猪**每秒刷一行**（见 `Sleep.start()` 注释）。
			#   玩家按键则**必须有反馈**，否则就是"按了没反应"。
			Log.ev("睡眠", "还不困（疲劳 %.0f%%），睡不着" % [sl.fatigue_ratio() * 100.0])
	_sleep_key_prev = key_down

	# **睡着时不行动**：不读方向、不举疾跑意图（躺着不可能在跑）。
	# ⚠ 这一条必须挡在"举疾跑意图"之前 —— 否则睡着的角色仍在举意图，会白扣体力。
	if sl != null and not sl.can_act():
		_prev = Vector2i.ZERO
		_step_acc = 0.0
		var sp_asleep := creature.get_component(Sprint) as Sprint
		if sp_asleep != null:
			sp_asleep.request(false)
		return

	#
	# 【疾跑意图每帧都举，但只在"真的在走"时才举 true】`Sprint.request()` 只是"举这一帧的意图"，
	#   结算在 `Sprint.tick()`。每帧都调用（含 dir==零时举 false）是为了清掉松手后的残留意图；
	#   但**站原地按住 Shift 不该算跑步**——否则原地空转烧体力、甚至跑空。故举意条件 = 有方向 且 按住 Shift。
	var dir := read_dir()
	var sprint := creature.get_component(Sprint) as Sprint
	if sprint != null:
		sprint.request(dir != Vector2i.ZERO and Input.is_action_pressed(ACTION_SPRINT))
	if dir == Vector2i.ZERO:
		_prev = dir
		return
	# ⚠ 显式标类型：`creature` 在组件基类里是 `Node`，`creature.current_speed()` 是 Variant，
	#   用 `:=` 会 Parse Error（本项目已复发多次，见事实文档 §2.4 坑 7）。
	var speed: float = creature.current_speed()
	var gate: float = _gate_seconds(speed)
	# 决策1：按住连续走 —— 攒够一个 gate 就走一格
	#        （HOLD_MOVE=false 时改成"方向变了才算一次按下"的边沿触发）
	var fire: bool = (_step_acc >= gate) if HOLD_MOVE else (dir != _prev and _step_acc >= gate)
	_step_acc += dt
	if not fire:
		_prev = dir
		return
	_submit(dir)
	_prev = dir

## 执行一次迈步：意图先过干扰层，再交 GridMover。
## 走不动时**不重置计时**（越界/被占/被否决都会返回 false）→ 下一帧继续试，
## 与 Brain 的"退化游荡、下次再试"是同一种容错风格。
func _submit(dir: Vector2i) -> void:
	_intent.submit(dir)
	_intent.apply(creature)                       # 干扰层挂点（v1 直通，不改 dir）
	if _intent.dir == Vector2i.ZERO:
		return                                    # 干扰层有权把意图清空（将来的"僵住"）
	var mover := creature.get_component(GridMover) as GridMover
	if mover == null:
		return
	if mover.try_step(_intent.dir):
		_step_acc = 0.0

# ---------------- 输入读取 ----------------

## 一次迈步需要等的秒数（游戏分钟）：`move_interval / current_speed`。
## 【为什么收成一个方法】它是"步频随身体/疾跑变化"的**唯一定义域** —— 写在 tick 里一次、
##   又写在 debug_state() 里一次，就会出现"调了上限忘了另一边"的经典债。
##   `MIN_SPEED` 地板保证再慢也有个有限的 gate（"真不能动"由协议 2 否决，不靠这里）。
## ⚠ 上限**不需要**钳：`Creature.current_speed()` 内部已经钳到 `SPRINT_SPEED_MAX`，
##   所以疾跑最多把 gate 缩到 1/4，不会出现"零帧迈步"。
func _gate_seconds(speed: float) -> float:
	var mi: float = 0.8
	if creature != null and creature.def != null:
		mi = creature.def.move_interval
	return mi / maxf(speed, MIN_SPEED)

## 读键盘方向 → 4 向之一（零向量 = 没按）。
## 【为什么取"主轴"】网格只有 4 向（`GridMover.DIRS`），斜按（W+A）时必须择一，
##   否则会得到 (1,-1) 这种非法方向。取绝对值大的那一轴（并列时优先水平，手感更稳）。
func read_dir() -> Vector2i:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v.length_squared() < 0.0001:
		return Vector2i.ZERO
	if absf(v.x) >= absf(v.y):
		return Vector2i.RIGHT if v.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if v.y > 0.0 else Vector2i.UP

## 调试自述（生成日志 + 调试器检查器里的 debug/components/player_brain 行）
## 【为什么把疾跑状态并进来】否则"速度=2.00"这个数字看着像个 bug ——
##   光看本行看不出它是疾跑加成还是哪个系数写错了。并进来就自解释了。
func debug_state() -> String:
	var d := read_dir()
	var name: String = DIR_NAMES.get(d, "停")
	var speed: float = creature.current_speed()
	var sp := creature.get_component(Sprint) as Sprint
	var tail := ""
	if sp != null:
		tail = " %s" % sp.debug_state()
	return "玩家 输入=%s 速度=%.2f 步频%.2fs%s" % [name, speed, _gate_seconds(speed), tail]
