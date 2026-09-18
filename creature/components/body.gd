class_name Body
extends CreatureComponent

## 部位组件（数据驱动）：部位清单来自 CreatureDef.body_parts。
## 总血 = 各部位之和；出血会随时间掉血（在 TimeSystem 时钟下）。
## 断肢 -> 该部位 hp 归零 -> 通过「移动许可协议」让宿主走不动（涌现式，不查表）。
##
## 【纪律】本组件不认识 GridMover，GridMover 也不认识这里 —— 只通过
##   allows_movement() 这个协议钩子对话。

var parts: Array[BodyPart] = []

func setup(host: Node) -> void:
	super.setup(host)
	parts.clear()
	if creature.def != null:
		for pdef in creature.def.body_parts:
			parts.append(BodyPart.new(pdef))

## 事件驱动：**只处理正在出血的部位**。没有出血就一个都不碰，
## 不再像以前那样每帧把所有部位全量扫一遍。
func tick(dt: float) -> void:
	for part in parts:
		if part.bleeding <= 0.0 or part.hp <= 0.0:
			continue
		part.hp = maxf(part.hp - part.bleeding * dt, 0.0)
		if part.hp <= 0.0:
			# 血已流光，出血状态随之结束。
			# （否则这个值会永远留着，将来一加治疗就会立刻「复流」。）
			part.bleeding = 0.0
		_note(part)

## 唯一的受伤入口。任何伤害来源（调试、将来的战斗/坠落/环境）都走这里，
## 确保「扣血 → 状态变化 → 日志」只有一套逻辑，不会各处各写一遍。
func hurt(part: BodyPart, damage: float, bleed: float = 0.0) -> void:
	if part == null or damage <= 0.0:
		return
	part.apply_damage(damage)
	if bleed > 0.0:
		part.add_bleeding(bleed)
	_note(part)

## 部位跨阈值时打日志（去重，不刷屏）
func _note(part: BodyPart) -> void:
	if part.hp <= 0.0:
		if not part._down_logged:
			part._down_logged = true
			Log.ev("受伤", "%s %s 失能 (0/%.0f)" % [creature.tag(), part.def.label, part.def.max_hp])
		return
	if not part._half_logged and part.ratio() < 0.5:
		part._half_logged = true
		var cat := "失血" if part.bleeding > 0.0 else "受伤"
		Log.ev(cat, "%s %s 掉到 50%% 以下 (%.0f/%.0f)" % [creature.tag(), part.def.label, part.hp, part.def.max_hp])

# ---------------- 协议实现 ----------------

## 向宿主报告事实：要害部位被打到 0 = 我已到死境。
## **不自己执行死亡** —— 执行由 Creature.check_dead_state() 在 tick 末尾统一接线。
func is_lethal() -> bool:
	return is_vital_down()

func lethal_reason() -> String:
	for p in parts:
		if p.def.is_vital and not p.function_ok():
			return "%s 要害失能" % p.def.label
	return ""

## 移动许可：只要部位定义里存在「支撑」类肢体（limb_types 含 "stance"），
## 就要求至少一条还活着；没有任何支撑肢体的物种（鱼/蛇等）不受限。
## 「哪条算腿」来自数据，不看 category 字符串。
## GridMover 通过协议问这个答案，因此**加别的移动限制（被捆/眩晕）不需要改 GridMover**。
func allows_movement() -> bool:
	return can_locomote()

func debug_state() -> String:
	var pstr: Array[String] = []
	for p in parts:
		pstr.append("%s%.0f" % [p.def.label, p.hp])
	return "血=%.0f/%.0f 部位{%s}" % [total_hp(), total_max(), " ".join(pstr)]

# ---------------- 查询 ----------------

## 是否有要害部位归零。「哪个部位是要害」来自数据字段 is_vital。
func is_vital_down() -> bool:
	for p in parts:
		if p.def.is_vital and not p.function_ok():
			return true
	return false

## 能否移动：见 allows_movement()
func can_locomote() -> bool:
	var has_stance := false
	for p in parts:
		if p.def.has_limb_type("stance"):
			has_stance = true
			if p.hp > 0.0:
				return true
	return not has_stance

func total_hp() -> float:
	var s := 0.0
	for p in parts:
		s += p.hp
	return s

func total_max() -> float:
	var s := 0.0
	for p in parts:
		s += p.def.max_hp
	return s

func part_by_id(id: String) -> BodyPart:
	for p in parts:
		if p.def.id == id:
			return p
	return null

## 调试：随机给一个部位造成伤害 + 出血（走统一的 hurt() 入口）
func random_wound() -> BodyPart:
	if parts.is_empty():
		return null
	var part: BodyPart = parts[creature.rng.randi_range(0, parts.size() - 1)]
	var dmg: float = creature.rng.randf_range(15.0, 45.0)
	var bl: float = creature.rng.randf_range(1.0, 4.0)
	Log.ev("受伤", "%s %s -%.1f 出血+%.1f/s (调试致伤)" % [creature.tag(), part.def.label, dmg, bl])
	hurt(part, dmg, bl)
	return part
