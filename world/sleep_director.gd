extends Node

## 睡眠导演（2026-09-21 建 · 2026-09-22 加「视野过渡」）—— 主角睡觉时：
##   **把时间加速** + **把画面缓缓推近压暗**，醒了立刻恢复。
##
## ══════════════════════════════════════════════════════════════════
## 一、为什么这件事**不能**写在 `Sleep` 组件里
## ══════════════════════════════════════════════════════════════════
##   `TimeSystem.speed` 是**全局**的 —— 它一改，整张地图的生物、草场、需求全都按新倍率走。
##   而"谁睡觉值得让全世界加速"是**编排层的策略**，不是生物自身的属性：
##     · 一只猪睡了，世界当然不该加速；
##     · 只有**主角**睡了才该加速。
##   ⇒ 组件只描述**状态**（`Sleep.is_sleeping()`），**策略**放在这里。
##     这与 `main.gd` 里"谁在扮演玩家由编排层决定"是同一条纪律。
##
## ══════════════════════════════════════════════════════════════════
## 二、为什么必须**加速**而不是"跳过"
## ══════════════════════════════════════════════════════════════════
##   用户 2026-09-21 拍板走"把夜晚当后台"这条路线。关键区别：
##     · **跳过** = 不模拟 —— 那夜里就没有危险了，"睡觉"变成无风险的免费回血；
##     · **加速** = 照常逐帧模拟，只是不逐帧看 —— 危险、寒冷、生育、草生长**全都照常发生**。
##   ⇒ 用户问过"玩家难道就看着角色躺那么久吗"。答案是：**夜里其实没东西可看**
##     （实测猪在夜里 93% 的时间在睡，画面几乎静止）。所以加速 + 醒来给反馈，
##     既解决了"干等"，又没有把风险抹掉。
##
##   ⚠ 倍率上限的物理依据：`TimeSystem.tick` 走 `_physics_process`（默认 60Hz），
##     所以 `speed = 60` 时 dt = 1 游戏分/物理帧 —— 再往上画面就开始"跳格"了。
##     取 30：一夜（20:00→06:00 = 600 游戏分）= **20 真实秒**，仍在舒适区间。
##
## ══════════════════════════════════════════════════════════════════
## 三、★★ 视野过渡：为什么"过渡进度"和"时间倍率"必须在同一个节点里 ★★
## ══════════════════════════════════════════════════════════════════
##   这是本功能最容易做错的地方，且**错了看不出来**（画面照样在渐变）。
##
##   入睡过渡是 **5.5 真实秒**。如果那 5.5 秒里时间已经是 30 倍速：
##       5.5 × 30 = 165 游戏分 = **2.75 个游戏小时**
##   而**一夜只有 600 游戏分** —— 光是过渡就会吃掉整个夜晚的 **27%**。
##   玩家按一下 R，什么都没看清，天就亮了。
##
##   ⇒ **过渡期间 `speed = 1`；只有过渡跑完（`t` 到 1）才允许加速。**
##     这条因果依赖决定了架构：`t` 和 `speed` 必须是**同一个节点持有的两个状态**，
##     不能一个放 UI、一个放 world。所以都归这里。
##
##   而两个**视觉消费者**（`SleepFade` 暗角 / `CameraRig` 推近）只需要听一个 `float` ——
##   它们**不认识 `Sleep`、也不认识时间倍率**，将来加音频 / 手柄震动不用动任何一处。
##
## ══════════════════════════════════════════════════════════════════
## 四、它怎么知道"主角是谁"
## ══════════════════════════════════════════════════════════════════
##   订阅 `EventBus.player_spawned` —— 与 `PlayerHud` / `CameraRig` 同一套路，
##   于是 `main.gd` 不必记得"生成主角后还要喂这里一口"（少一处接线疏漏）。
##   主角死了 / 被清屏了 -> `is_instance_valid` 为假 -> 立刻恢复正常倍率**并把画面拉回**。
##   ⚠ 后半句同样必须：不拉回来的话**主角死后画面会永远暗着**。

## 主角睡着时的时间倍率。见文件头第二节。
const SLEEP_SPEED := 30.0
## 正常倍率。
const NORMAL_SPEED := 1.0

## —— 视野过渡参数（全是占位，跑出来再调）——
## 入睡过渡时长（**真实秒**，用户要 5-6 秒）。见文件头第三节。
const FALL_SECONDS := 5.5
## 自然醒过渡时长（真实秒）。
## ⚠ **故意比入睡短**：真实的入睡是几分钟的渐进过程，醒来是突发的（睁眼那一下就已经清醒七八成）。
##   "入睡慢、醒来快"的不对称是"真"与"假"最明显的分界线。
##   要完全对称就把这里改成 5.5（一个常量的事）。
const WAKE_SECONDS := 4.0
## 状态机的兜底：`FALLING` 连续这么多帧还没跑完就强制进 `ASLEEP`。
## 【为什么要有】`_view` 一旦卡在 `FALLING`，`_desired_speed()` 就**永远不加速** ——
##   睡眠功能静默失效，而且**画面上看不出来**（还在渐变）。状态机不能有死路。
const FALL_MAX_FRAMES := 1800

## 视野状态。见文件头第三节的图。
enum View { AWAKE, FALLING, ASLEEP, RISING }

var _player: Creature = null
var _sleep: Sleep = null
## 上一次真正写进 `TimeSystem.speed` 的值。只在**变化时**写，
## 免得每帧都去碰一个全局单例（也免得将来别人改了倍率又被本节点按回去）。
var _applied := NORMAL_SPEED

var _view: View = View.AWAKE
var _u := 0.0            # 过渡的**时间进度** 0..1（线性走）
var _t := 0.0            # 视觉强度 0..1（由 `_u` 经曲线算出，见 `_shape()`）
var _emitted := -1.0     # 上次广播出去的 t（-1 = 还没广播过）
var _fall_frames := 0    # FALLING 已持续多少帧（兜底用）

func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	# 场景里可能已经有主角了（本节点若排在 Main 之后 _ready）—— 兜一次底。
	var m := get_parent()
	if m != null and "player" in m and m.player != null:
		_on_player_spawned(m.player)
	_emit(true)             # 开局先广播一次 t=0，让消费者有个确定初值

func _on_player_spawned(c: Node) -> void:
	_player = c as Creature
	_sleep = _player.get_component(Sleep) as Sleep if _player != null else null

func _process(dt: float) -> void:
	_step_view(dt)
	_apply_speed()
	_emit(false)

## 视野状态机。图见文件头第三节。
func _step_view(dt: float) -> void:
	# —— 主角没了 / 死了：**立刻**回到清醒视野 ——
	# ⚠ 不处理的话画面会永远停在暗着的样子（倍率那边是同一个道理，见文件头第四节）。
	if _sleep == null or _player == null or not is_instance_valid(_player) or not _player.is_alive():
		_reset_view()
		return

	var sleeping := _sleep.is_sleeping()
	match _view:
		View.AWAKE:
			if sleeping:
				_view = View.FALLING
				_u = 0.0
				_fall_frames = 0
		View.FALLING:
			_fall_frames += 1
			_u = minf(_u + dt / FALL_SECONDS, 1.0)
			# 入睡途中被吵醒 / 取消 —— 按"醒来"处理（惊醒则一帧归零）
			if not sleeping:
				_begin_rising()
			elif _u >= 1.0 or _fall_frames > FALL_MAX_FRAMES:
				_view = View.ASLEEP
		View.ASLEEP:
			if not sleeping:
				_begin_rising()
		View.RISING:
			_u = minf(_u + dt / WAKE_SECONDS, 1.0)
			if _u >= 1.0:
				_view = View.AWAKE
				_u = 0.0
			elif sleeping:
				# 醒来途中又被叫去睡（比如 R 连按）—— **从当前进度接着往下沉**。
				# ⚠ 必须反解出 `u`，不能重置为 0：那会让 `t` 跳变（见 EASE_P 的注释）。
				_u = _unshape(View.FALLING, _shape(View.RISING, _u))
				_view = View.FALLING
				_fall_frames = 0
	_t = _shape(_view, _u)

## 醒来的**唯一入口**：靠 `Sleep.wake_kind()` 决定"缓缓醒"还是"一帧醒"。
##
## ⚠ 用类型化的 `wake_kind()` 而不是比字符串 —— 见 `Sleep.Wake` 枚举的注释。
func _begin_rising() -> void:
	# 当前在哪（用**旧** view + 旧 u 算，因为下面就要改 `_view` 了）
	var here := _shape(_view, _u)
	# 惊醒（附近有动静）**不走过渡** —— 从最暗到全亮一帧完成，这个"跳"本身就是"惊"。
	if _sleep.wake_kind() == Sleep.Wake.DISTURBED:
		_view = View.AWAKE
		_u = 0.0
		_t = 0.0
		return
	# 温和醒来：从当前进度往回拉。⚠ 同样必须反解，不能把 `_u` 重置为 0 ——
	# 否则入睡到一半被打断时 `t` 会**突然跳到 1.0**（画面先变最暗再往回走）。
	_view = View.RISING
	_u = _unshape(View.RISING, here)
	_t = here

func _reset_view() -> void:
	_view = View.AWAKE
	_u = 0.0
	_t = 0.0
	_fall_frames = 0

## 把线性的 `_u` 整形视觉强度 `t`。**非线性是"真"的关键 —— 线性过渡一眼就假。**
##
##   入睡 `t = u^EASE_P` —— **先慢后快**（越来越沉，真实入睡就是这个手感）。
##   醒来 `t = (1−u)^EASE_P` —— **先快后慢**（一睁眼就回来大半，剩下是"缓过来"）。
##   ⇒ **同一条曲线、镜像使用**，所以下面一个 `_unshape()` 就够两个方向用。
##
## ══════════════════════════════════════════════════════════════════
## 【为什么不是 smoothstep】—— 踩过才改的，别改回去
## ══════════════════════════════════════════════════════════════════
##   smoothstep（`u²(3−2u)`）视觉上更好看，但**它的反函数没有便宜解**（三次方程）。
##   而本状态机**必须**有一个反函数 —— 见 `_unshape()` 与"过渡中途改方向"。
##   第一版用了 smoothstep 且没有反解，实测直接炸：
##     · 醒来途中（`_u`≈0.97）再按 R 入睡 → `_u` 接着走 → **0.1 秒就跳进 `ASLEEP`**
##       → 时间瞬间变 ×30（本该还有 5.5 秒的入睡过渡被整个跳过）
##     · 入睡途中（t=0.5）被打断 → `_u` 重置为 0 → `t` **突然跳到 1.0**（画面先变最暗）
##   `u^1.5` 的观感与 smoothstep 同向（都是先慢后快），但反函数是廉价的 `pow`。
##   想更沉就把指数调大（1.5 → 2.0，越大人睡越"慢热"）。
const EASE_P := 1.5

static func _shape(view: View, u: float) -> float:
	var k := clampf(u, 0.0, 1.0)
	match view:
		View.AWAKE:  return 0.0
		View.ASLEEP: return 1.0
		View.FALLING: return pow(k, EASE_P)
		View.RISING:  return pow(1.0 - k, EASE_P)
	return 0.0

## `_shape()` 的反函数：由当前视觉强度 `t` 反解出**时间进度** `u`。
##
## 【为什么必须有】过渡**中途改方向**时（醒来途中又按 R 睡、入睡途中被叫醒），
##   不能把 `_u` 重置为 0 —— 那会让 `t` 跳变（上面 EASE_P 的注释里写了实测后果）。
##   正确做法是"**从当前进度接着走**"：先把 `t` 反解成新方向下的 `u`，再继续推进。
static func _unshape(view: View, t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	match view:
		View.FALLING: return pow(k, 1.0 / EASE_P)
		View.RISING:  return 1.0 - pow(k, 1.0 / EASE_P)
	return 0.0

## 该用多快的倍率。
##
## ★ **只看 `_view == ASLEEP`，不看 `is_sleeping()`** —— 这正是文件头第三节那条：
##   过渡期间（`FALLING`）**不能**加速，否则 5.5 秒会跑掉 165 游戏分。
func _desired_speed() -> float:
	return SLEEP_SPEED if _view == View.ASLEEP else NORMAL_SPEED

func _apply_speed() -> void:
	var want := _desired_speed()
	if is_equal_approx(want, _applied):
		return
	_applied = want
	TimeSystem.speed = want
	Log.ev("睡眠", "时间倍率 -> ×%.0f" % want)

func _emit(force: bool) -> void:
	if not force and is_equal_approx(_t, _emitted):
		return
	_emitted = _t
	EventBus.sleep_view_changed.emit(_t)

# ---------------- 供调试 / 自检 ----------------

## 当前是否处于加速态。
func is_accelerated() -> bool:
	return _applied > NORMAL_SPEED

## 当前视觉强度（0=清醒视野，1=完全入睡）。供自检用。
func view_t() -> float:
	return _t

## 当前视野状态名（供自检 / 日志）。
func view_state_text() -> String:
	match _view:
		View.FALLING: return "入睡中"
		View.ASLEEP:  return "熟睡"
		View.RISING:  return "醒来中"
		_:            return "清醒"
