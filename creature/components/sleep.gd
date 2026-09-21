class_name Sleep
extends CreatureComponent

## 睡眠组件（2026-09-21）—— 把「睡觉」做成一个**跨帧的状态**，而不是一次决策。
##
## ══════════════════════════════════════════════════════════════════
## 一、为什么必须独立成组件：**睡眠是状态，不是驱动**
## ══════════════════════════════════════════════════════════════════
##   改之前，猪的"睡觉"是 `Brain` 轮盘里的一个 `rest` 驱动 —— 每 1 秒重掷一次，
##   所谓"睡 100 分钟"其实是靠"下一次决策在 100 分钟之后"这个 hack 撑出来的。
##   于是三件事**根本没地方放**：
##     · 睡多深（浅睡/深睡）        · 睡了多久、还欠多少觉
##     · **被打断**（每帧都要判，不能等下次决策）
##   ⇒ 新开本组件持有这些状态；`Brain` 只问它一句"我现在能行动吗"。
##     `Brain` 的轮盘一行不用改，`rest` 驱动退化成"困了想睡"的**意愿**。
##
## ══════════════════════════════════════════════════════════════════
## 二、四个状态
## ══════════════════════════════════════════════════════════════════
##   ```
##   清醒 AWAKE ──入睡──> 入睡中 ONSET ──> 熟睡 ASLEEP ──被唤醒──> 醒神 WAKING ──> 清醒
##                 (2 游戏分)              (回疲劳)          (3 游戏分，迟钝)
##   ```
##   · **入睡中**：躺下了但还没睡着。这一小段是"还能反悔"的窗口（也是被吵醒最便宜的时候）。
##   · **熟睡**：按 `RECOVER_PER_MIN` 回疲劳；**感知半径缩小**（见协议），这就是"脆弱"。
##   · **醒神**：刚醒，速度与感知都打折 —— **被提前吵醒要有代价**，否则"睡一觉"就无风险了。
##
## ══════════════════════════════════════════════════════════════════
## 三、两个唤醒条件（用户 2026-09-21 拍板）
## ══════════════════════════════════════════════════════════════════
##   **① 自然醒** —— 疲劳回够了（`WAKE_FATIGUE_RATIO`），或睡到了上限（`MAX_SLEEP_MIN`）。
##   **② 附近有东西在动** —— 半径 `WAKE_RADIUS` 内有**正在移动**的生物。
##
##   ⚠ **为什么是"在动"而不是"在附近"**：如果任何生物靠近就醒，主角身边一直躺着猪群，
##     那就**永远睡不着**。改成"有东西在动"之后：
##     · 睡着的猪不吵醒你（它们不动）—— 符合直觉；
##     · **走过来的东西**才吵醒你 —— 这才是真正的威胁；
##     · 而且它顺手给了高草一个新用途：**猪藏进高草你就感知不到**（`Perception._scan()`
##       跳过隐蔽者），所以"在草丛里睡"天然更安静。
##     ⚠ 现在场上还没有真正的敌人，所以"任何生物"都算 —— 将来有捕食者时，
##       应该把判据收窄成"捕食者"（见 `_intruder_nearby()` 的注释）。
##
## ══════════════════════════════════════════════════════════════════
## 四、它管什么 / 不管什么
## ══════════════════════════════════════════════════════════════════
##   管：睡眠状态机、睡眠期间的恢复、唤醒判定、睡/醒带来的身体折扣。
##   不管：**时间加速**（那是编排层的策略，见 `world/sleep_director.gd`）、
##        **怎么显示**（UI 的事）、**困了想不想睡**（`Brain` 的 rest 驱动的事）。

## 睡眠状态。见文件头第二节。
enum State { AWAKE, ONSET, ASLEEP, WAKING }

## 躺下到真正睡着的延迟（游戏分）。这一小段是"还能反悔"的窗口。
const ONSET_MIN := 2.0

## 醒神时长（游戏分）。刚醒这段时间速度与感知都打折 —— **被吵醒要有代价**。
const WAKING_MIN := 3.0

## 熟睡时每秒（游戏分）回多少疲劳。
##
## 【为什么是 0.1 而不是原来的 0.2】原来 `Brain.SLEEP_RECOVER_RATE = 0.2`：
##   一夜（20:00→06:00 = 600 游戏分）能回 **120 点**，而满槽只有 **100 点**
##   ⇒ **猪的疲劳永远顶在 100 —— "满槽 2 个游戏日"这个设计从来没生效过。**
##   按"一夜刚好抵一天消耗"反推：白天 16 小时 × 实测平均 1.65× 劳累 ≈ **55 点**，
##   所以应该是 `55 / 600 ≈ 0.09`。取 0.1（一夜回 60 点，略有余量）。
const RECOVER_PER_MIN := 0.1

## 疲劳回到这个比例就**自然醒**。
const WAKE_FATIGUE_RATIO := 0.95

## 一次最多睡多久（游戏分 = 12 游戏小时）。
## 【为什么要有上限】`world/sleep_director.gd` 会把时间加速 30 倍 ——
##   没有上限的话"疲劳回不满就永远睡"会把加速态无限拖下去。
const MAX_SLEEP_MIN := 720.0

## 唤醒半径（格）。这个半径内有**正在移动**的生物就醒。
const WAKE_RADIUS := 4

## 「正在移动」的判定窗口（游戏分）。与 `GridMover.WALK_GLOW` 同一个量级 ——
##   生物约 1 秒走 1 格，用 2 秒的窗口把迈步之间的空隙盖住。
const MOTION_WINDOW := 2.0

## 醒神期的移动速度折扣（协议 6）。
const WAKING_SPEED := 0.8

## 熟睡时的感知半径倍率（协议 9）。0.35 → 半径 6 变成 2。
##
## 【为什么不是 0】缩到 0 就永远醒不过来了。留一点点，让"有东西走到很近"仍然能吵醒你，
##   同时大幅降低"远处路过"的打扰。这就是"睡觉时脆弱"的量化。
const ASLEEP_SENSE := 0.35

## 本组件的调试前缀（协议 3 的自述用）
const TAG := "睡眠"

var _state: State = State.AWAKE
var _timer := 0.0          # 当前状态的剩余/已用时间（游戏分），含义随状态变
var _slept := 0.0          # 本次已睡多久（游戏分）
var _just_woke := false    # 本帧刚醒（供 `SleepDirector` 立刻把时间倍速降回来）
var _wake_reason := ""     # 唤醒原因（日志与 UI 用）

func requires() -> Array:
	# 硬依赖两条：
	#   Needs      —— 疲劳值住在它那里（睡眠只读写它，不另存一份）
	#   Perception —— 判"附近有没有东西在动"
	return [Needs, Perception]

func setup(host: Node) -> void:
	super.setup(host)
	_state = State.AWAKE
	_timer = 0.0
	_slept = 0.0
	_just_woke = false
	_wake_reason = ""

# ---------------- 生命周期 ----------------

func tick(dt: float) -> void:
	_just_woke = false
	match _state:
		State.ONSET:
			_timer -= dt
			_slept += dt
			# 入睡途中也可能被吵醒 —— 这时候最便宜（还没睡进去）
			if _intruder_nearby():
				_wake("附近有动静", State.AWAKE)
			elif _timer <= 0.0:
				_state = State.ASLEEP
				Log.ev("睡眠", "%s 睡着了" % creature.tag())
		State.ASLEEP:
			_slept += dt
			_recover(dt)
			if _intruder_nearby():
				_wake("附近有动静", State.WAKING)
			elif _fatigue_ratio() >= WAKE_FATIGUE_RATIO:
				_wake("睡够了", State.WAKING)
			elif _slept >= MAX_SLEEP_MIN:
				_wake("睡太久了", State.WAKING)
		State.WAKING:
			_timer -= dt
			if _timer <= 0.0:
				_state = State.AWAKE
				Log.ev("睡眠", "%s 完全清醒" % creature.tag())
		_:
			pass

## 睡着时不行动 —— 由 `PlayerBrain` / `Brain` 每帧问。
func can_act() -> bool:
	return _state == State.AWAKE or _state == State.WAKING

## 现在是不是"躺下睡了"（含入睡中）。`SleepDirector` 靠它决定要不要加速。
func is_sleeping() -> bool:
	return _state == State.ONSET or _state == State.ASLEEP

func state() -> State:
	return _state

func state_text() -> String:
	match _state:
		State.ONSET: return "入睡中"
		State.ASLEEP: return "熟睡"
		State.WAKING: return "醒神"
		_: return "清醒"

## 本帧刚醒（`SleepDirector` 用它把时间倍速立刻降回来）。
func just_woke() -> bool:
	return _just_woke

func wake_reason() -> String:
	return _wake_reason

## 本次睡了多久（游戏分）。
func slept_minutes() -> float:
	return _slept

# ---------------- 对外动作 ----------------

## 开始睡觉。返回 false = 现在不该睡（已经睡着 / 不困）。
## 【为什么不困也允许】用户原话是"想睡觉的时候就开始睡觉" —— 所以**不设硬门槛**，
##   只是"已经睡够了"时给个提示并拒绝（否则会出现"躺下一秒就起来"的空动作）。
func start() -> bool:
	if is_sleeping():
		return false
	if _fatigue_ratio() >= WAKE_FATIGUE_RATIO:
		Log.ev("睡眠", "%s 还不困（疲劳 %.0f%%）" % [creature.tag(), _fatigue_ratio() * 100.0])
		return false
	_state = State.ONSET
	_timer = ONSET_MIN
	_slept = 0.0
	_wake_reason = ""
	Log.ev("睡眠", "%s 躺下准备睡（疲劳 %.0f%%）" % [creature.tag(), _fatigue_ratio() * 100.0])
	return true

## 主动叫醒（玩家按键 / 将来被攻击）。
func wake_up(reason: String = "主动醒来") -> void:
	if _state == State.AWAKE:
		return
	_wake(reason, State.WAKING)

# ---------------- 协议实现 ----------------

## 协议 3：调试自述。
func debug_state() -> String:
	if _state == State.AWAKE:
		return "%s 清醒 疲劳%.0f%%" % [TAG, _fatigue_ratio() * 100.0]
	return "%s %s 已睡%.0f分 疲劳%.0f%%" % [
		TAG, state_text(), _slept, _fatigue_ratio() * 100.0]

## 协议 6：**醒神期走得慢**（被提前吵醒的代价）。
func move_speed_factor() -> float:
	return WAKING_SPEED if _state == State.WAKING else 1.0

## 协议 9（新增）：**睡着时感知半径大幅缩小**。
## `Perception` 会把它乘到自己的半径上 —— 这就是"睡觉时脆弱"的落点。
func sense_multiplier() -> float:
	return ASLEEP_SENSE if _state == State.ASLEEP else 1.0

# ---------------- 内部 ----------------

func _wake(reason: String, next: State) -> void:
	_state = next
	_timer = WAKING_MIN if next == State.WAKING else 0.0
	_just_woke = true
	_wake_reason = reason
	Log.ev("睡眠", "%s 醒了（%s），已睡 %.0f 游戏分" % [creature.tag(), reason, _slept])
	_slept = 0.0

## 按 `RECOVER_PER_MIN` 回疲劳。走 `Needs.restore()` —— 与吃/喝/取暖同一个入口。
func _recover(dt: float) -> void:
	var needs := creature.get_component(Needs) as Needs
	if needs == null:
		return
	needs.restore(FATIGUE_ID, RECOVER_PER_MIN * dt)

## 半径 `WAKE_RADIUS` 内有没有**正在移动**的生物。见文件头第三节。
##
## ⚠ 现在**任何生物**都算 —— 场上还没有真正的敌人。
##   将来有捕食者时，把这里换成"按 def 问捕食关系"，而不是"任何生物"。
func _intruder_nearby() -> bool:
	var perc := creature.get_component(Perception) as Perception
	if perc == null:
		return false
	for c in perc.nearby_creatures(WAKE_RADIUS):
		var cr := c as Creature
		if cr == null:
			continue
		var mv := cr.get_component(GridMover) as GridMover
		if mv != null and mv.moved_recently(MOTION_WINDOW):
			return true
	return false

func _fatigue_ratio() -> float:
	var needs := creature.get_component(Needs) as Needs
	if needs == null:
		return 1.0
	var n := needs.need_by_id(FATIGUE_ID)
	return n.ratio() if n != null else 1.0

## 用哪条需求当「疲劳」。与 `Needs.FATIGUE_ID` / `Brain.FATIGUE_ID` 同字面量。
const FATIGUE_ID := "fatigue"
