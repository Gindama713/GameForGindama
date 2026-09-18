class_name Needs
extends CreatureComponent

## 需求组件（数据驱动）：激活哪些需求来自 CreatureDef.active_needs。
## 在 TimeSystem 时钟下衰减；数值占位待调。
## 物种裁剪：鱼不挂本组件（不需要口渴），狼挂全套 —— 全在 CreatureDef 数据里。
##
## 【纪律】本组件不认识 Body，也不认识任何具体组件 —— 只通过协议与宿主/别人对话。

var needs: Array[Need] = []

func setup(host: Node) -> void:
	super.setup(host)
	needs.clear()
	if creature.def != null:
		for ndef in creature.def.active_needs:
			needs.append(Need.new(ndef))

func tick(dt: float) -> void:
	for n in needs:
		if n.value > 0.0:
			n.value = maxf(n.value - n.def.drain_rate * dt, 0.0)
			if n.is_depleted() and not n._depleted_logged:
				n._depleted_logged = true
				var tail := "（致命）" if n.def.depleted_is_lethal else ""
				Log.ev("需求", "%s %s 见底%s" % [creature.tag(), n.def.label, tail])

# ---------------- 协议实现 ----------------

## 报告事实：标了 depleted_is_lethal 的需求见底 = 我已到死境。
## 不自己执行死亡 —— 执行由 Creature.check_dead_state() 统一接线。
## 这一条把「饿不死 / 渴不死 / 冻不死」的洞堵上了。
func is_lethal() -> bool:
	for n in needs:
		if n.def.depleted_is_lethal and n.is_depleted():
			return true
	return false

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
