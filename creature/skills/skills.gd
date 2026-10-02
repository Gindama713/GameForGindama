class_name Skills
extends CreatureComponent

const MAX_LEVEL := 100
const FIRST_LEVEL_XP := 10.0
const XP_GROWTH := 0.2

var attributes: Dictionary = {} # 属性 id -> 0..100，先天倾向
var _levels: Dictionary = {} # 技能 id -> 0..100
var _experience: Dictionary = {} # 技能 id -> 当前等级内的经验


func setup(host: Node) -> void:
	super.setup(host)
	attributes.clear()
	_levels.clear()
	_experience.clear()
	for id: StringName in SkillDef.ATTRIBUTE_NAMES:
		var base: float = float(creature.def.attribute_base.get(id, 50.0))
		attributes[id] = clampf(base + creature.rng.randf_range(-creature.def.attribute_spread,
			creature.def.attribute_spread), 0.0, 100.0)
	for definition in creature.def.skill_catalog.skills:
		_levels[definition.id] = 0
		_experience[definition.id] = 0.0


func inherit_attributes(a: Skills, b: Skills) -> void:
	for id: StringName in SkillDef.ATTRIBUTE_NAMES:
		var av: float = a.attribute(id) if a != null else attribute(id)
		var bv: float = b.attribute(id) if b != null else attribute(id)
		attributes[id] = clampf((av + bv) * 0.5 + creature.rng.randf_range(-5.0, 5.0), 0.0, 100.0)
	# 练出的等级和经验不会遗传。


func attribute(id: StringName) -> float:
	return float(attributes.get(id, 50.0))


func level(id: StringName) -> int:
	return int(_levels.get(id, 0))


func experience(id: StringName) -> float:
	return float(_experience.get(id, 0.0))


func experience_to_next(id: StringName) -> float:
	return 0.0 if level(id) >= MAX_LEVEL else FIRST_LEVEL_XP + XP_GROWTH * level(id)


func progress_ratio(id: StringName) -> float:
	var needed: float = experience_to_next(id)
	return 1.0 if needed <= 0.0 else clampf(experience(id) / needed, 0.0, 1.0)


func practice(id: StringName, effort: float = 1.0) -> void:
	if effort <= 0.0 or level(id) >= MAX_LEVEL:
		return
	var definition: SkillDef = creature.def.skill_catalog.find(id)
	if definition == null:
		return
	var aptitude: float = _aptitude(definition)
	var gained: float = definition.experience_per_effort * effort * clampf(1.0 + (aptitude - 50.0) / 250.0, 0.8, 1.2)
	var current: int = level(id)
	var total: float = experience(id) + gained
	while current < MAX_LEVEL and total >= FIRST_LEVEL_XP + XP_GROWTH * current:
		total -= FIRST_LEVEL_XP + XP_GROWTH * current
		current += 1
	_levels[id] = current
	_experience[id] = 0.0 if current == MAX_LEVEL else total


func _aptitude(definition: SkillDef) -> float:
	return attribute(definition.primary_attribute) * 0.7 + attribute(definition.secondary_attribute) * 0.3


func debug_state() -> String:
	return "技能%d项" % creature.def.skill_catalog.skills.size()
