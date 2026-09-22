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
	# 年龄身体素质：幼崽/老年体弱 → 同样的打击掉更多血（Aging.damage_multiplier）
	var mult := 1.0
	var ag := creature.get_component(Aging) as Aging
	if ag != null:
		mult = ag.damage_multiplier()
	part.apply_damage(damage * mult)
	if bleed > 0.0:
		part.add_bleeding(bleed)
	_note(part)

## 部位跨阈值时打日志（去重，不刷屏）
func _note(part: BodyPart) -> void:
	if part.hp <= 0.0:
		if not part.down_logged():
			part.mark_down_logged()
			Log.ev(Log.CAT_HURT, "%s %s 失能 (0/%.0f)" % [creature.tag(), part.def.label, part.def.max_hp])
		return
	if not part.half_logged() and part.ratio() < 0.5:
		part.mark_half_logged()
		var cat := Log.CAT_BLEED if part.bleeding > 0.0 else Log.CAT_HURT
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

## 移动速度协议（协议 6）：**腿断得越多走得越慢** = 存活 stance 肢体 / 全部 stance 肢体。
##   四条腿断两条 → 0.5（半速）；断三条 → 0.25；全断 → 0（且 allows_movement() 已先否决）。
## 没有 stance 肢体的物种（鱼/蛇）→ 1.0（不受限）。
## ⚠ 这是**连续量**，与 allows_movement() 的 0/1 否决分工不同（见 creature_component.gd 协议 6 注释）。
func move_speed_factor() -> float:
	return stance_ratio()

## 伤势染色协议（协议 7）：把**最重的那处伤**折算成一个颜色，供表现层给精灵染色。
##
## 【为什么取"最重"而不是全身平均】用户要看的是"哪只手受伤了"这个**事实** ——
##   全身平均值会把"一只手断了另一只手完好"平摊成"轻伤"，把信息抹平。
##   取最重的那处 = 屏幕上一眼能看出"这人身上有重伤"。
## 【逐部位的具体位置】只在这个面板/精灵级别做不到（精灵是一张整图）——
##   所以**逐部位上色**由 UI 层做（player_panel 的部位色块），这里给的是**整体色调**。
func injury_tint() -> Color:
	var worst := BodyPart.Severity.HEALTHY
	for p in parts:
		if p.severity() > worst:
			worst = p.severity()
	return SEVERITY_TINT.get(worst, Color(1, 1, 1, 1))

## 伤势档位 → 整体染色。**与 UI 层同一套档位**（BodyPart.severity()），
## 只是这里给的是"整只生物看起来如何"，UI 那边是"哪个部位看起来如何"。
const SEVERITY_TINT := {
	BodyPart.Severity.HEALTHY:  Color(1.00, 1.00, 1.00),
	BodyPart.Severity.LIGHT:    Color(1.00, 0.93, 0.62),
	BodyPart.Severity.MODERATE: Color(1.00, 0.78, 0.45),
	BodyPart.Severity.SEVERE:   Color(1.00, 0.55, 0.50),
	BodyPart.Severity.DISABLED: Color(0.85, 0.42, 0.42),
}

## 存活支撑肢体的比例（1 = 全好，0 = 全断）。无 stance 肢体 → 1。
func stance_ratio() -> float:
	var total := 0
	var alive := 0
	for p in parts:
		if not p.def.has_limb_type("stance"):
			continue
		total += 1
		if p.hp > 0.0:
			alive += 1
	if total == 0:
		return 1.0
	return float(alive) / float(total)

func debug_state() -> String:
	var pstr: Array[String] = []
	for p in parts:
		pstr.append("%s%.0f" % [p.def.label, p.hp])
	return "血=%.0f/%.0f 部位{%s} 腿%.0f%%" % [total_hp(), total_max(), " ".join(pstr), stance_ratio() * 100.0]

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
	Log.ev(Log.CAT_HURT, "%s %s -%.1f 出血+%.1f/s (调试致伤)" % [creature.tag(), part.def.label, dmg, bl])
	hurt(part, dmg, bl)
	return part
