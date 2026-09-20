class_name Sprint
extends CreatureComponent

## 疾跑组件（2026-09-20）。
##
## 【一句话】让宿主可以"跑起来"（速度 ×2），代价是**疲劳（= 体力）掉得快得多**。
##
## ── 设计核心：**体力就是疲劳，同一条，只是看的方向不同**（用户拍板 2026-09-20）──
##   疲劳值 100 = 精神饱满 = **体力满 = 能跑最久**；
##   疲劳值   0 = 精疲力竭 = **体力空 = 跑不动**（且既有的疲劳减速生效，走路也只剩 55%）。
##   于是**本组件不新开第二条数值轴**：
##     "还剩多少体力" → 读 `Needs` 的 fatigue 需求（不自己存）
##     "跑步扣体力"   → 写 `Needs` 的 fatigue 需求（不自己扣）
##   这与 `brain.gd` 里那段「速度定义域只有一处」的教训是同一条纪律：
##   **同一事实两处算法 = 迟早朝不同方向漂移。**
##
## ⚠ **但"同一根槽"不等于"同一把尺子"**（2026-09-20 修正，见 `DRAIN_PER_SEC` 注释）：
##   疲劳的**基线**消耗（走路/活着）是为猪的作息调的 → 满槽 2 个游戏日；
##   冲刺的**额外**消耗是为玩家的手感调的 → 期望满槽 10 秒量级。
##   两者差 28.8 倍，所以冲刺速率是**独立绝对值**，不写成"基线的 N 倍"。
##   **共用一根槽（存储）+ 各用一把尺（速率）** —— 这两件事不矛盾。
##
## ── 它管什么 / 不管什么 ──
##   管：**现在能不能跑**（体力够不够、有没有在冷却）+ **跑起来多快**（协议 6b）+ **跑起来多费**。
##   不管：**往哪跑**（Brain / PlayerBrain 的事）、**体力条怎么显示**（UI 的事）、
##        **活着本身费多少**（那是 `need_fatigue.tres` 的 `drain_rate`，本组件不碰）。
##
## ── 为什么"能不能跑"要做成**滞回**（两个阈值）而不是一个阈值 ──
##   如果起跑线与断跑线是同一个值（比如都是 0.1），会抖：
##   体力刚好卡在 0.1 时，这帧 0.101 能跑 → 下帧 0.099 断跑 → 再下帧又 0.101…**
##   于是画面上是"跑一格走一格"的抽搐。用**两个阈值**（起跑 0.15 / 断跑 0.02）隔开，
##   一旦开跑就允许跑到几乎见底，中间的差值就是防止抖动的缓冲。
##
## ── 恢复：只有休息/睡觉才回（用户拍板）──
##   走路本身仍在按基线消耗（见 `need_fatigue.tres` 的 drain_rate），所以原地站着不特别回体。
##   回复动作由 `Brain` 的 rest 驱动（`SLEEP_RECOVER_RATE`）负责，**不在本组件里做** ——
##   本组件不指挥"你该歇了"，只回答"你现在能不能跑"。

## 用哪条需求当「体力」。**与 Needs.FATIGUE_ID / Brain.FATIGUE_ID 同一个字面量** ——
##   目前三处各写一遍是既有的债（见 needs.gd 注释），本组件随大流不引入第四个写法。
const STAMINA_ID := "fatigue"

## 跑步速度倍率（用户拍板：快两倍）。
const SPEED_MULT := 2.0

## 冲刺时**每秒（游戏分）**扣多少疲劳。用户拍板 2026-09-20。
##
## ── 为什么是"绝对值"而不是"基线的 N 倍"（这是本轮最重要的一次修正）──
##   用户原话：**"疲劳100 = 体力100，能跑 10 秒；跑完疲劳变 90，那就只能跑 9 秒。"**
##   反推： 10 秒烧 10 点 → **1.00 点/秒**。
##
##   最初把它写成 `need_fatigue.drain_rate × 2.5`，结果满槽能跑 **1152 秒（19 分钟）**，
##   与用户的 10 秒差了 **两个数量级**。根因不是"该乘几倍"，而是**这两件事根本不该共用一把尺子**：
##
##   | 用途 | 谁在调 | 尺度 |
##   |---|---|---|
##   | 疲劳基线 `drain_rate = 0.03472` | 为**猪的作息**调（睡一觉顶一整天）| 满槽 **2.00 游戏日** |
##   | 冲刺消耗 | 为**玩家的手感**调（10 秒爆一下）| 满槽 **10 真实秒** |
##
##   两者相差 **28.8 倍**。硬用一个乘数绑住，必然有一方被毁：
##   若为了让冲刺 10 秒见底而把基线涨到 0.4，疲劳槽就只剩 250 分（4.2 真实分钟），
##   猪会一天累垮 5.8 次、作息彻底崩 —— 而猪的疲劳账是**极脆弱**的（`brain.gd` 有实测记录）。
##
##   ⇒ **拆开**：走路/站着的消耗仍归 `need_fatigue.tres`（**一个字不动**）；
##     冲刺的消耗归本常量。两者各自独立、各自可调。
##
##   ⚠ 用户"跑步是走路 2~3 倍"的直觉**依然成立** —— 由两个绝对值相除自然得出：
##     `1.00 / 0.03472 ≈ 28.8` 倍的**速率比**，体现在体感上就是"冲刺时那条槽肉眼可见地掉"。
##     只是这个比值从此是**结论**，不再是**输入**。
##
## 【换算】1 游戏分 = 1 真实秒（见 time_system.gd），所以本值 = "每秒烧几点"。
##   满体力可跑 = (100 − 100×`STOP_MIN_RATIO`) / 本值 = 98 / 1.0 = **98 真实秒**。
##   ⚠ 这里量纲是"游戏分"，与 `remaining_run_seconds()` 的返回一致 —— 但那个函数名里的
##     "seconds" 指的是**游戏分**（1:1 映射到真实秒），别被名字骗了。
const DRAIN_PER_SEC := 1.0

## 起跑门槛：体力比例低于此值就**起不了步**（但已经在跑的不打断 —— 见 `_keep`）。
const START_MIN_RATIO := 0.15

## 断跑门槛：跑着掉到此值以下 → **强制脱力**。必须明显低于起跑门槛，否则会抖动（见文件头注释）。
const STOP_MIN_RATIO := 0.02

## 脱力后的强制冷却（游戏分 = 真实秒）。
## 【为什么需要它】没有冷却的话，体力掉到 0.02 的下一个 tick 只要回到 0.03 就又能起步，
##   在高消耗下会变成"跑一格歇一格"的抽搐。冷却期让"脱力"成为一个**真的状态**。
## 【取 5 秒的理由（2026-09-20 由 30 改小）】冲刺本身只有 ~98 秒的满槽时长，
##   罚站 30 秒 = 跑 1 秒罚 0.3 秒，太重了。5 秒足够让"我把自己跑废了"被感知到，
##   又不会把"脱力"变成一个比"跑"还长的惩罚。**数值待实测再调。**
const EXHAUST_COOLDOWN := 5.0

## 本组件的调试前缀（协议 3 的自述用）
const TAG := "疾跑"

var _running := false          # 当前是否在跑（唯一事实来源）
var _cooldown := 0.0           # >0 = 脱力冷却中
var _run_seconds := 0.0        # 本次连跑累积了多久（游戏分）—— 纯统计，逻辑不依赖它

## —— 「这一帧跑步」的意图位（**每帧重置**）——
## 【为什么不是"request 直接开/关"】踩过的坑：玩家大脑每帧都会调 `request(没按Shift=false)`，
##   于是它**每帧都在关** —— 任何别的来源（将来的"疼痛/恐慌夺走控制"、
##   被野兽追时的自动冲刺）刚 `request(true)`，下一帧就被玩家大脑关掉，永远赢不了。
##   所以改成：**`request(true)` = 举起这一帧的意图**；`tick()` 处理完消耗后**统一放下**。
##   谁都可以举，谁都举不掉别人的 —— 这是"多个来源竞争同一个动作"的正确形态，
##   与 `GridMover.can_move()` 的"全票通过"、`allows_movement()` 的 0/1 否决是同一种思路。
var _want_this_frame := false
## 谁在这一帧请求了跑步（调试自述用，人可读）
var _requested_by: String = ""

func requires() -> Array:
	return [Needs]             # 硬依赖：没有 Needs 就没有"体力"可扣，疾跑无从谈起

func setup(host: Node) -> void:
	super.setup(host)
	_running = false
	_cooldown = 0.0
	_run_seconds = 0.0
	_want_this_frame = false
	_requested_by = ""

# ---------------- 生命周期 ----------------

## 每帧推进。**顺序很重要**：先结算"这一帧有没有人想跑"（据此开/停），
## 再按 dt 扣体力，最后**清掉意图位**等下一帧重新举。
##
## 【为什么清在这里而不是在 tick 开头】`Creature._on_tick` 按**组件插入顺序**遍历，
##   而各组件（Brain / PlayerBrain）的 `tick()` 也在这一趟里跑。
##   若在本函数开头就清，则"排在本组件之后"的大脑这一帧举的意�图会被立刻丢掉。
##   放在**末尾**清，语义是："本帧内任何人举的意图都已生效，现在开始收下一帧的。"
func tick(dt: float) -> void:
	# ① 冷却计时（脱力中，谁想跑都没用）
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - dt, 0.0)
		_running = false
		_want_this_frame = false
		_requested_by = ""
		return

	# ② 依据本帧意图 + 体力门槛，决定跑 / 不跑
	if _want_this_frame and not _running:
		if not _gate_blocked() and stamina_ratio() >= START_MIN_RATIO:
			_start()
	if not _want_this_frame and _running:
		_stop()

	# ③ 跑着就扣体力
	if _running:
		_drain_stamina(dt)
		_run_seconds += dt
		if stamina_ratio() <= STOP_MIN_RATIO:
			_exhaust()

	# ④ 收下这一帧的意图位，等下一帧重新举
	_want_this_frame = false
	_requested_by = ""

## 举起「这一帧我想跑」的意图。**由任何有能力请求跑步的来源每帧调用**
## （玩家按住 Shift / 动物决定逃命 / 将来的"疼痛恐慌自动冲刺"）。
##
## 返回**本帧实际是否在跑** —— 大脑据此算步频，不必自己判断体力。
##
## 【它不"开启"跑步，只"举意"】真正的开关在 `tick()` 里统一结算（见那里的说明）。
##   ⇒ 多个来源可以同时举意，谁也不会把别人关掉。
##   ⇒ 松手不需要发"停止"信号：没人举意，`tick()` 自己就停了。
##
## ⚠ 由于结算发生在 `tick()`，本函数返回的是**上一帧结算出的状态**。
##   对使用者无影响：大脑读它只是为了算 gate，而 gate 用的 `current_speed()`
##   读的也是同一个 `_running` —— 两者天然同步，不会出现"说在跑、实际没跑"的错配。
func request(wanted: bool) -> bool:
	if wanted:
		_want_this_frame = true
		_requested_by = _caller_hint()
	return _running

# ---------------- 对外查询 ----------------

func is_running() -> bool:
	return _running

func is_exhausted() -> bool:
	return _cooldown > 0.0

## 脱力还剩多久（游戏分）。供 UI 显示"喘气中 12s"。
func cooldown_left() -> float:
	return _cooldown

## 当前体力比例（0..1）。**就是疲劳比例**，不是另存的一份数值。
## 无 Needs / 没挂 fatigue 需求 → 返回 1.0（视为"永远跑得动"，不影响宿主）。
func stamina_ratio() -> float:
	var needs := _stamina_need()
	return needs.ratio() if needs != null else 1.0

## 按当前体力，还能跑多久。**返回值的单位是游戏分，而 1 游戏分 = 1 真实秒** ——
## 所以数字可以直接当"秒"读（函数名里的 seconds 就是这个意思）。
##
## ⚠ 单位陷阱（实测踩过）：`stamina_ratio()` 是**比例**（0..1），而 `_sprint_drain_per_second()`
##   是**绝对点数**。两者**不能直接相除** —— 必须先乘回 `max_value` 换成绝对点数，
##   否则得到的数字会小 `max_value` 倍（满体力显示"还能跑 1 秒"而不是 98 秒）。
##
## 【对照用户举例】满体力 → `(100 − 2) / 1.0` = **98 秒**；
##   体力 90 → `(90 − 2) / 1.0` = **88 秒**（≈ 满值的 89.8%）。
##   用户原话是"能跑 10 秒、剩 90 就只能跑 9 秒"—— 比例关系完全一致（线性）；
##   绝对时长从 10 秒放宽到 98 秒，是因为 10 秒在 130×130 的图上只够跑 40 格，
##   连一片草原外沿都出不去，"追/躲"会变成一件做不到的事。**若嫌长，只调 `DRAIN_PER_SEC`。**
func remaining_run_seconds() -> float:
	if _gate_blocked():
		return 0.0
	var n := _stamina_need()
	if n == null:
		return INF                        # 没挂体力需求 -> 视为无限（与 stamina_ratio 的 1.0 一致）
	var left_points := maxf(n.value - n.def.max_value * STOP_MIN_RATIO, 0.0)
	var rate := _sprint_drain_per_second()
	if rate <= 0.0:
		return INF
	return left_points / rate

# ---------------- 协议实现 ----------------

## 协议 6b：疾跑加成。跑着的时候 ×2，否则 ×1（不加成）。
## ⚠ 基类会再钳到 `SPRINT_SPEED_MAX`，所以这里直接给 2.0 是安全的。
func sprint_speed_factor() -> float:
	return SPEED_MULT if _running else 1.0

## 协议 3：调试自述。
func debug_state() -> String:
	if _cooldown > 0.0:
		return "%s 脱力(剩%.0fs)" % [TAG, _cooldown]
	if _running:
		return "%s 跑中 体力%.0f%% 已跑%.0fs 还能%.0fs[%s]" % [
			TAG, stamina_ratio() * 100.0, _run_seconds, remaining_run_seconds(), _requested_by]
	return "%s 站 体力%.0f%% 可跑%.0fs" % [TAG, stamina_ratio() * 100.0, remaining_run_seconds()]

# ---------------- 内部 ----------------

## 谁在举意（仅供调试自述）。**不做成参数** —— 那会污染所有调用点的签名，
##   而它只是给人看的一句话，不该成为接口的一部分。
## ⚠ 靠调用栈猜来源有点"魔法"，但这里只影响一行日志文本，不影响任何逻辑；
##   若哪天它变复杂了，就该老实加一个 `request(wanted, source)` 参数。
func _caller_hint() -> String:
	var st := get_stack()
	for i in range(1, mini(st.size(), 4)):
		var f: Dictionary = st[i]
		var fn := String(f.get("function", ""))
		if fn == "tick" or fn.begins_with("_") or fn == "":
			continue
		return fn
	return "?"

func _start() -> void:
	_running = true
	_run_seconds = 0.0
	Log.ev("疾跑", "%s 起步（体力 %.0f%%，速度系数 %.2f）" % [
		creature.tag(), stamina_ratio() * 100.0, creature.current_speed()])

func _stop() -> void:
	_running = false
	_run_seconds = 0.0

## 跑空了：断跑 + 进冷却。这是"脱力"这个状态的**唯一切换点**。
func _exhaust() -> void:
	_running = false
	_run_seconds = 0.0
	_cooldown = EXHAUST_COOLDOWN
	Log.ev("疾跑", "%s 跑脱力了，需喘 %d 秒" % [creature.tag(), int(EXHAUST_COOLDOWN)])

## 按 dt（游戏分）扣体力。**唯一写入口**。
##
## 【为什么直接改 `n.value` 而不走 `Needs.restore(负数)`】
##   `restore()` 的语义是"**补回**"（吃/喝/睡都走它），它内部是 `minf(value + amount, max)`。
##   传负数进它虽然能"扣"，但语义上是在借用一个为"补"设计的入口做反方向的事 ——
##   将来 `restore()` 加了"补回来时顺便清 `_depleted_logged`"这类逻辑时，扣减会被一起误伤。
##   所以这里**显式扣**，并自己维护 `_depleted_logged` 与 `Needs.tick()` 的口径一致。
##   ⚠ 代价：`_depleted_logged` 是 `Need` 的私有字段（GDScript 无真私有，但纪律上要克制）。
##     这样做是因为"跑空"必须留下日志 —— 否则玩家不知道自己为什么忽然跑不动了。
func _drain_stamina(dt: float) -> void:
	var n := _stamina_need()
	if n == null:
		return
	# 注意单位：`_sprint_drain_per_second()` 返回的是**绝对点数**，可直接乘 dt（游戏分 = 真实秒）。
	n.value = maxf(n.value - _sprint_drain_per_second() * dt, 0.0)
	# 见底日志要与 Needs.tick() 的口径一致，否则会出现"疲劳见底"有日志、
	# 而"跑空"没日志（或反过来）的不一致。
	if n.is_depleted() and not n._depleted_logged:
		n._depleted_logged = true
		Log.ev("需求", "%s %s 见底（跑空了）" % [creature.tag(), n.def.label])

## 本组件冲刺时每秒扣多少体力（绝对点数）。
## **公式只在这里写一遍** —— `remaining_run_seconds()` 与 `_drain_stamina()` 都调它，
## 免得"改了一处忘了另一处"（本项目已复发多次，见事实文档 §2.4）。
##
## ⚠ 只返回 `DRAIN_PER_SEC`，**不乘** `need_fatigue.tres` 的 `drain_rate`。
##   为什么见常量注释：两者的时间尺度差 28.8 倍，乘在一起必有一方被毁。
##   注意 `Needs.tick()` 同帧也按基线扣了一次（0.03472），所以冲刺时的**实际总消耗**是
##   `1.00 + 0.03472 = 1.03472/秒`；那 3.5% 的基线量可忽略，且语义清晰（"活着"+"在冲刺"）。
func _sprint_drain_per_second() -> float:
	return DRAIN_PER_SEC

func _stamina_need() -> Need:
	var needs := creature.get_component(Needs) as Needs
	if needs == null:
		return null
	return needs.need_by_id(STAMINA_ID)

## 身体是否不允许跑（协议 2 的硬否决，如腿全断）。
## 【为什么在这里再问一次】协议 2 已经在 `GridMover.can_move()` 拦了"走"，
##   但"跑"是更早的意图 —— 断了腿还显示"跑中"、体力照扣，是假信息。
func _gate_blocked() -> bool:
	for comp in creature.get_components():
		if not comp.allows_movement():
			return true
	return false
