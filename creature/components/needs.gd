class_name Needs
extends CreatureComponent

## 需求组件（数据驱动）：激活哪些需求来自 CreatureDef.active_needs。
## 在 TimeSystem 时钟下衰减；数值占位待调。
## 物种裁剪：鱼不挂本组件（不需要口渴），狼挂全套 —— 全在 CreatureDef 数据里。
##
## 【纪律】本组件不认识 Body，也不认识任何具体组件 —— 只通过协议与宿主/别人对话。

## 疲劳对移动速度的最大拖累（占位）：累到 0 → 只剩 55% 速度；精神饱满 → 1.0。
## ⚠ 本系数是**全物种统一**的：`Creature.locomotion_speed()` 聚合协议 6，AI(PlayerBrain/Brain)
##   都读同一个聚合值 —— 疲劳的减速在这里定义一次，两种大脑都受益（2026-09-20 统一，见 brain.gd）。
const FATIGUE_ID := "fatigue"
const FATIGUE_SLOW := 0.55

var needs: Array[Need] = []

func setup(host: Node) -> void:
	super.setup(host)
	needs.clear()
	if creature.def != null:
		for ndef in creature.def.active_needs:
			needs.append(Need.new(ndef))

func tick(dt: float) -> void:
	# 劳累档位（协议 8）：静止 1× / 走路 2× / 跑步 4×。**只作用在疲劳上** ——
	# 跑起来不会更饿更渴（那是另一套规则，将来真要加就再加一条协议，别塞进这里）。
	var exert: float = creature.exertion_level()
	for n in needs:
		if n.value > 0.0:
			var mult := exert if n.def.id == FATIGUE_ID else 1.0
			drain(n.def.id, n.def.drain_rate * mult * dt)

# ---------------- 协议实现 ----------------

## 报告事实：标了 depleted_is_lethal 的需求见底 = 我已到死境。
## 不自己执行死亡 —— 执行由 Creature.check_dead_state() 统一接线。
## 这一条把「饿不死 / 渴不死 / 冻不死」的洞堵上了。
func is_lethal() -> bool:
	for n in needs:
		if n.def.depleted_is_lethal and n.is_depleted():
			return true
	return false

## 移动速度协议（协议 6）：**越累走得越慢**。
##   fatigue 比例 1（精神饱满）→ 1.0；0（精疲力竭）→ FATIGUE_SLOW(0.55)；中间线性插值。
## 疲劳**不致命**（设计如此，见 need_def.gd 注释），它的后果就是「更想歇 + 走得更慢」。
## 无 Needs 组件 / 该物种没挂 fatigue 需求 → 1.0（不影响移动）。
func move_speed_factor() -> float:
	var n := need_by_id(FATIGUE_ID)
	if n == null:
		return 1.0
	return lerpf(FATIGUE_SLOW, 1.0, clampf(n.ratio(), 0.0, 1.0))

func lethal_reason() -> String:
	for n in needs:
		if n.def.depleted_is_lethal and n.is_depleted():
			return "%s 耗尽" % n.def.label
	return ""

func debug_state() -> String:
	var nstr: Array[String] = []
	for n in needs:
		nstr.append("%s%.0f" % [n.def.label, n.value])
	return "需求{%s}" % " ".join(nstr)

# ---------------- 查询 / 操作 ----------------

## 扣减某项需求的**唯一入口**（与 `restore()` 对称）。返回 true = 本次调用让它**刚刚见底**。
##
## ── 【为什么必须收口】──
##   "扣需求"原本散在三处，各有各的速率（都是合理的），但都要做同一件事：
##   **"扣到 0 为止 + 见底只报一次日志"**：
##     · 本组件按 `drain_rate` 扣（活着的基本消耗）
##     · `Sprint` 按自己的 `DRAIN_PER_SEC` 扣（冲刺）
##     · `Thermal` 按自己的 `NIGHT_DRAIN_PER_SEC` 扣（夜里受冻）
##   而去重标记 `Need._depleted_logged` 是**私有字段** —— 于是后两个组件直接读写它，
##   这就是"跨组件侵入私有状态"。后果有三：
##     ① **没有一处知道"一条需求可以被哪些途径扣掉"**；
##     ② 加第四种扣减（中毒 / 流血 / 暴晒）时会再抄一遍那 3 行；
##     ③ 抄的时候极易漏掉日志口径 —— **历史上真的漏过**
##        （"疲劳见底"有日志、而"跑空"没日志，排查时完全看不出为什么忽然跑不动）。
##   ⇒ 收进本函数：扣减 + 封底 + 见底日志。调用方只给"扣多少"，不再碰任何私有字段。
##
## `reason` 会并进日志，用来区分"活着消耗"与"冲刺 / 受冻"这类额外扣减：
##   例如「见底（致命，冻僵了）」「见底（跑空了）」。留空则只报致命性。
func drain(id: String, amount: float, reason: String = "") -> bool:
	if amount <= 0.0:
		return false
	var n := need_by_id(id)
	if n == null:
		return false
	n.value = maxf(n.value - amount, 0.0)
	if not n.is_depleted() or n._depleted_logged:
		return false
	n._depleted_logged = true
	var notes: Array[String] = []
	if n.def.depleted_is_lethal:
		notes.append("致命")
	if not reason.is_empty():
		notes.append(reason)
	var tail := "" if notes.is_empty() else "（%s）" % "，".join(notes)
	Log.ev("需求", "%s %s 见底%s" % [creature.tag(), n.def.label, tail])
	return true

## 恢复某项需求（将来的「吃 / 喝 / 取暖 / 睡觉」都调这个）。
## 返回 false = 该需求没激活（如给鱼喂水）。
func restore(id: String, amount: float) -> bool:
	var n := need_by_id(id)
	if n == null:
		return false
	n.value = minf(n.value + amount, n.def.max_value)
	if n.value > 0.0:
		n._depleted_logged = false     # 缓过来了，下次见底要重新报
	return true

func need_by_id(id: String) -> Need:
	for n in needs:
		if n.def.id == id:
			return n
	return null
