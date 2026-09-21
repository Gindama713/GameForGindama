class_name Sprint
extends CreatureComponent

## 疾跑组件（2026-09-20 建 · 2026-09-21 按用户口径重做为**两条独立的条**）。
##
## 【一句话】跑起来速度 ×2，代价是**体力**（一条短促的爆发资源）；体力见底就跑不动，喘一会儿才回得来。
##
## ══════════════════════════════════════════════════════════════════
## 一、★ 生物身上有**两条**条，别把它们混成一条 ★（用户 2026-09-21 拍板）
## ══════════════════════════════════════════════════════════════════
##
##   | | **疲劳条** | **体力条** |
##   |---|---|---|
##   | 归谁管 | `Needs`（`need_fatigue.tres`） | **本组件** |
##   | 尺度 | 慢 —— 满槽 **2 个游戏日** | 快 —— 满槽 **100/15 ≈ 6.7 秒** |
##   | 上限 | 固定 100 | **= 疲劳条的当前值**（跟着掉！）|
##   | 怎么回 | **只有睡觉**（`Brain` 的 rest 驱动） | 停下就回（`STAMINA_RECOVER_PER_SEC`）|
##   | 谁在耗 | 活着（1×）· 走路（2×）· **跑步（4×）** | **只有跑步**（15/秒）|
##
##   ⇒ **体力条的上限 = 疲劳值**。于是"跑一会儿疲劳掉到 80"之后，体力上限也变成 80，
##     就只能跑 `80 / 15 ≈ 5.3 秒` —— **累了就是跑不久，而且这件事不需要额外写规则**。
##
##   ⚠ **别把两条并成一条派生值**（我在 2026-09-21 上午就这么错过一次）：
##     那会把"疲劳的账"和"冲刺的账"焊在同一根尺子上，而两者的时间尺度差 288 倍，
##     必然有一方被毁。**它们共用的是"上限"这个关系，不是同一个数值。**
##
## ══════════════════════════════════════════════════════════════════
## 二、疲劳的"劳累档位"（协议 8，用户拍板 1× / 2× / 4×）
## ══════════════════════════════════════════════════════════════════
##   `1×` 静止（基准） · `2×` 走路（`GridMover` 给） · `4×` **跑步（本组件给）**
##
##   ⇒ 跑步让疲劳条掉得**比走路快一倍、比静止快三倍**（相对基准）。
##     注意这是"消耗**倍率**"，不是"额外扣一笔" —— 疲劳条本身仍是那条 2 个游戏日的槽。
##
##   ⚠ 这条把"跑步"和"长期疲劳"真正接上了：**一直冲刺赶路会实打实地烧掉疲劳条**
##     （跑 1 游戏分 ≈ 静止 4 游戏分的账）。这也是用户要的"疲劳条可以用很久，但不是免费"。
##
## ══════════════════════════════════════════════════════════════════
## 三、数值从哪来（2026-09-21 查了 5 个同类游戏）
## ══════════════════════════════════════════════════════════════════
##   | 游戏 | 关键做法 |
##   |---|---|
##   | **CDDA**（本项目主要参考） | 跑步 = 移动消耗减半（**2× 速度，与本组件一致**）；消耗是走路的 **7 倍**；体力越低移动消耗越高；**走路会缓慢回体力**（站着时的 1/4） |
##   | **Project Zomboid** | 四档命名状态（25/50/75/90%）；**用掉 50% 就禁止疾跑**；走路会"大幅削减甚至抵消恢复"（**必须停下才回**） |
##   | **塞尔达 BotW** | 体力圈画在**角色身边**；力竭时不能用道具 |
##   | **黑暗之魂** | 池子 80~160、回复 45/秒 → **满槽 3.6 秒回满**；动作后**有一小段延迟**才开始回 |
##   | **Minecraft** | **根本没有体力条** —— 跑步直接吃饥饿值，饥饿 ≤6 不能跑 |
##
##   ⇒ 结论：**冲刺是"短爆发"**（我们 6.7 秒，量级正确）+ **必须能喘回来**（旧版只能靠睡觉，
##     跑一次就没了）+ **停下后有一小段延迟才开始回**（学黑暗之魂）。
##
## ── ⚠ 旧版 98 秒的复盘：当时那个理由是错的 ──
##   2026-09-20 把满槽定成 98 秒，理由是"10 秒只够跑 40 格，连一片草原外沿都出不去"。
##   **这个论证站不住**：草原长半轴实测 8.1 / 7.7（直径约 16 格），40 格能横穿 **2.5 次**；
##   湖离草边只有 `LakeDef.anchor_gap = 10` 格。**用户最初的"能跑 10 秒"本来就是对的。**
##
## ══════════════════════════════════════════════════════════════════
## 四、它管什么 / 不管什么
## ══════════════════════════════════════════════════════════════════
##   管：**现在能不能跑**（体力够不够、有没有在冷却）+ **跑起来多快**（协议 6b）
##     + **跑起来多费**（协议 8 的 4×）+ **体力怎么涨落**。
##   不管：**往哪跑**（Brain / PlayerBrain）、**体力怎么显示**（`creature/sprint_arc.gd`）、
##        **疲劳条自己的账**（那是 `need_fatigue.tres` 的 `drain_rate`，本组件只通过协议 8 影响倍率）。

## 用哪条需求当**疲劳**（也就是体力上限的来源）。与 `Needs.FATIGUE_ID` / `Brain.FATIGUE_ID` 同字面量。
const STAMINA_ID := "fatigue"

## 跑步速度倍率（用户拍板：快两倍；**CDDA 的跑步也是"移动消耗减半"= 2×**，两者一致）。
const SPEED_MULT := 2.0

## 跑步时疲劳消耗的倍率（协议 8）。**用户拍板**：静止 1× / 走路 2× / 跑步 4×。
## 走路那一档由 `GridMover.exertion_level()` 给，本组件给的是跑步这一档，基类取 max。
const EXERTION_RUN := 4.0

## 跑步时每秒扣多少**体力**。**用户拍板：一秒 15**。
## ⇒ 满疲劳（100）能跑 `100 / 15 ≈ 6.67 秒`；疲劳掉到 80 就只能跑 `80 / 15 ≈ 5.33 秒`。
const STAMINA_DRAIN_PER_SEC := 15.0

## 不跑步时每秒回多少体力。`100 / 10 = 10 秒` 回满。
##
## 【为什么必须有它】旧版只能靠睡觉回（8.3 真实分钟），意味着"跑一次就没了"，
##   做不出"跑—歇—跑"的节奏。业界都会**停下来就回**（黑暗之魂 3.6 秒回满、
##   BotW 站着回得比走着快、CDDA 走路能回）。
## 【为什么比消耗慢】15 : 10 —— 让"歇"比"跑"略长一点，冲刺才不至于变成默认移动方式。
const STAMINA_RECOVER_PER_SEC := 10.0

## 停下后**多久才开始**回（游戏分）。抄黑暗之魂的"动作后有一小段延迟才开始回复"：
##   让"刚跑完那一下"有个可感知的停顿，而不是松手立刻回升。
const RECOVER_DELAY := 0.6

## 起跑门槛：体力比例低于此值就**起不了步**（但已经在跑的不打断 —— 见 `tick()`）。
## 【为什么不能是 0】若"有一点体力就能起步"，跑空后会变成"回一帧就跑一帧"的抽搐。
##   留 35% 的缓冲，跑空后要回 `0.35 × 上限 / 10` 秒才能再起步。
##   （Project Zomboid 更狠：**用掉 50% 就禁止疾跑**。取 0.35 比它宽松。）
const START_MIN_RATIO := 0.35

## 断跑门槛：跑着掉到此值以下 → **强制力竭**。必须明显低于起跑门槛，否则会抖动。
const STOP_MIN_RATIO := 0.02

## 力竭后的强制冷却（游戏分 = 真实秒）。期间**不能起跑**，但**体力照常在回**
##   （"喘气"本来就该是恢复过程；冷却只是禁止"刚喘上一口就又冲出去"）。
## 【为什么是 3 秒】满槽只跑 6.7 秒，罚站 5 秒就变成"跑 1 秒罚 0.75 秒"，太重了。
const EXHAUST_COOLDOWN := 3.0

## **没有疲劳需求时的兜底满值**（那种物种视为"永远跑得动"，与旧版行为一致）。
## ⚠ 它**不是**"体力满值"的定义 —— 满值一律读 `NeedDef.max_value`（见 `stamina_fill_ratio()`）。
##   把它当成满值写死会在"把 `need_fatigue.max_value` 改成 200"时静默错位。
const NO_NEED_FALLBACK := 100.0

## 本组件的调试前缀（协议 3 的自述用）
const TAG := "疾跑"

var _running := false          # 当前是否在跑（唯一事实来源）
var _cooldown := 0.0           # >0 = 力竭冷却中
var _run_seconds := 0.0        # 本次连跑累积了多久（游戏分）—— 纯统计，逻辑不依赖它

## **当前体力**（绝对值，0 .. `stamina_max()`）。
## ⚠ 上限**不是常数** —— 它等于疲劳值，会随着疲劳下降而下降（见文件头第一节）。
var _stamina := NO_NEED_FALLBACK
## 距"可以开始喘气"还剩多久（游戏分）。见 `RECOVER_DELAY`。
var _rest_timer := 0.0

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

## 「最近有没有人想跑」的余辉（游戏分）。**纯给表现层用**。
## 【为什么需要它】玩家按住 Shift 但体力不够时会"什么都不发生" —— 没有反馈。
##   本值让 `creature/sprint_arc.gd` 在这种情况下也把体力圆弧画出来，
##   于是"跑不动"变成看得见的（圆弧见底 / 泛红），而不是"按键坏了"。
var _request_glow := 0.0

func requires() -> Array:
	return [Needs]             # 硬依赖：体力上限就是疲劳值，没有 Needs 就无从谈起

func setup(host: Node) -> void:
	super.setup(host)
	_running = false
	_cooldown = 0.0
	_run_seconds = 0.0
	_stamina = stamina_max()   # 开局满体力（= 满疲劳）
	_rest_timer = 0.0
	_want_this_frame = false
	_requested_by = ""
	_request_glow = 0.0

# ---------------- 生命周期 ----------------

## 每帧推进。**顺序很重要**：先结算"这一帧有没有人想跑"（据此开/停），
## 再按 dt 记账，最后**清掉意图位**等下一帧重新举。
##
## 【为什么清在这里而不是在 tick 开头】`Creature._on_tick` 按**组件插入顺序**遍历，
##   而各组件（Brain / PlayerBrain）的 `tick()` 也在这一趟里跑。
##   若在本函数开头就清，则"排在本组件之后"的大脑这一帧举的意图会被立刻丢掉。
##   放在**末尾**清，语义是："本帧内任何人举的意图都已生效，现在开始收下一帧的。"
func tick(dt: float) -> void:
	_request_glow = maxf(_request_glow - dt, 0.0)

	# ① 冷却计时（力竭中，谁想跑都没用）—— 但**体力照常在回**（"喘气"就是恢复）
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - dt, 0.0)
		_running = false
		_recover_stamina(dt)
		_clamp_to_max()
		_want_this_frame = false
		_requested_by = ""
		return

	# ② 依据本帧意图 + 体力门槛，决定跑 / 不跑
	if _want_this_frame and not _running:
		if not _gate_blocked() and stamina_ratio() >= START_MIN_RATIO:
			_start()
	if not _want_this_frame and _running:
		_stop()

	# ③ 跑着就扣体力；没跑就（延迟后）回体力
	if _running:
		_drain_stamina(dt)
		_run_seconds += dt
		if stamina_ratio() <= STOP_MIN_RATIO:
			_exhaust()
	else:
		_recover_stamina(dt)

	# ④ 上限跟着疲劳走 —— 疲劳掉了，体力要被压到新的上限以下
	_clamp_to_max()

	# ⑤ 收下这一帧的意图位，等下一帧重新举
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
		_request_glow = 0.25           # 让表现层即使"跑不动"也能显示体力圆弧
	return _running

# ---------------- 对外查询 ----------------

func is_running() -> bool:
	return _running

func is_exhausted() -> bool:
	return _cooldown > 0.0

## 力竭还剩多久（游戏分）。供 UI 显示"喘气中 3s"。
func cooldown_left() -> float:
	return _cooldown

## **体力上限 = 疲劳值**（用户拍板）。见文件头第一节。
## 无 Needs / 该物种没挂疲劳需求 → 返回 `NO_NEED_FALLBACK`（视为"永远跑得动"）。
func stamina_max() -> float:
	var n := _stamina_need()
	return maxf(n.value, 0.0) if n != null else NO_NEED_FALLBACK

## 当前体力**绝对值**（0 .. `stamina_max()`）。供 UI 显示数字与画"上限刻度"。
func stamina() -> float:
	return _stamina

## 当前体力比例（0..1）= `体力 / 上限`。上限为 0（疲劳见底）时返回 0。
## 无疲劳需求 → 返回 1.0（视为"永远跑得动"，不影响宿主）。
func stamina_ratio() -> float:
	var n := _stamina_need()
	if n == null:
		return 1.0
	var maxv := stamina_max()
	if maxv <= 0.0:
		return 0.0
	return clampf(_stamina / maxv, 0.0, 1.0)

## **供表现层画体力圈**：体力占**满值**的比例。
##
## 【满值读数据，不写死】满值 = `NeedDef.max_value`（疲劳那条需求的 max）——
##   写死 100 的话，把 `need_fatigue.max_value` 改成 200 就会静默错位。
##
## 【为什么用绝对刻度，而不是"占当前上限的比例"】上限是动态的（= 疲劳值）。
##   若按"占上限的比例"画，**一个疲劳只剩 20 的角色，圈会画成满的** ——
##   而它其实只能跑 1.3 秒。按绝对刻度画，疲劳低的角色圈**天然就短**，
##   一眼就能看出"跑不久"（表现层就是靠这个把"上限在缩"传达出去的）。
func stamina_fill_ratio() -> float:
	var n := _stamina_need()
	var full := maxf(n.def.max_value, 0.0001) if n != null else NO_NEED_FALLBACK
	return clampf(_stamina / full, 0.0, 1.0)

## **表现层用**：现在该不该显示体力圆弧。
##   跑着 / 力竭冷却中 / 体力没满 / 刚刚有人想跑但跑不动 -> 显示。
##   回满且站着不动 -> 不显示（用户要求"跑起来才出现，停下几秒后淡出"）。
func gauge_visible() -> bool:
	if _running or _cooldown > 0.0 or _request_glow > 0.0:
		return true
	return _stamina < stamina_max() - 0.01

## 按当前体力，还能跑多久。**返回值的单位是游戏分，而 1 游戏分 = 1 真实秒** ——
## 所以数字可以直接当"秒"读。
##
## 【算法】用户原话："100/15"、"疲劳上限 80 了就 80/15" —— 就是 `体力 / 每秒消耗`。
func remaining_run_seconds() -> float:
	if _gate_blocked():
		return 0.0
	var rate := _sprint_drain_per_second()
	if rate <= 0.0:
		return INF
	return maxf(_stamina, 0.0) / rate

# ---------------- 协议实现 ----------------

## 协议 6b：疾跑加成。跑着的时候 ×2，否则 ×1（不加成）。
## ⚠ 基类会再钳到 `SPRINT_SPEED_MAX`，所以这里直接给 2.0 是安全的。
func sprint_speed_factor() -> float:
	return SPEED_MULT if _running else 1.0

## 协议 8：**跑步时疲劳消耗 ×4**（走路 2× 由 `GridMover` 给，基类取 max）。
func exertion_level() -> float:
	return EXERTION_RUN if _running else 1.0

## 协议 3：调试自述。
func debug_state() -> String:
	if _cooldown > 0.0:
		return "%s 力竭(剩%.0fs) 体力%.0f/%.0f" % [
			TAG, _cooldown, _stamina, stamina_max()]
	if _running:
		return "%s 跑中 体力%.0f/%.0f 已跑%.0fs 还能%.0fs[%s]" % [
			TAG, _stamina, stamina_max(), _run_seconds, remaining_run_seconds(), _requested_by]
	return "%s 站 体力%.0f/%.0f 可跑%.0fs" % [
		TAG, _stamina, stamina_max(), remaining_run_seconds()]

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
	Log.ev("疾跑", "%s 起步（体力 %.0f/%.0f，速度系数 %.2f）" % [
		creature.tag(), _stamina, stamina_max(), creature.current_speed()])

func _stop() -> void:
	_running = false
	_run_seconds = 0.0
	_rest_timer = RECOVER_DELAY        # 松手后要等一小段才开始喘（学黑暗之魂）

## 跑空了：断跑 + 进冷却。这是"力竭"这个状态的**唯一切换点**。
func _exhaust() -> void:
	_running = false
	_run_seconds = 0.0
	_cooldown = EXHAUST_COOLDOWN
	_rest_timer = RECOVER_DELAY
	Log.ev("疾跑", "%s 跑脱力了，需喘 %d 秒" % [creature.tag(), int(EXHAUST_COOLDOWN)])

## 按 dt（游戏分）扣体力。**唯一写入口**。
## ⚠ **不碰疲劳值** —— 疲劳那笔账由协议 8 的"倍率"影响（`Needs` 去扣），本组件不直接写它。
func _drain_stamina(dt: float) -> void:
	if _stamina_need() == null:
		return                         # 没有疲劳需求 -> 体力视为无限（永远跑得动）
	_stamina = maxf(_stamina - _sprint_drain_per_second() * dt, 0.0)
	_rest_timer = RECOVER_DELAY

## 「喘息」：不跑步时回体力。见 `STAMINA_RECOVER_PER_SEC` / `RECOVER_DELAY`。
func _recover_stamina(dt: float) -> void:
	if _rest_timer > 0.0:
		_rest_timer = maxf(_rest_timer - dt, 0.0)
		return
	_stamina = minf(_stamina + STAMINA_RECOVER_PER_SEC * dt, stamina_max())

## 把体力压到当前上限以内。**上限会变**（= 疲劳值），所以每帧都要做一次。
func _clamp_to_max() -> void:
	_stamina = clampf(_stamina, 0.0, stamina_max())

## 本组件冲刺时每秒扣多少体力。
## **公式只在这里写一遍** —— `remaining_run_seconds()` 与 `_drain_stamina()` 都调它。
func _sprint_drain_per_second() -> float:
	return STAMINA_DRAIN_PER_SEC

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
