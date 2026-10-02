class_name SkillDef
extends Resource

const ATTRIBUTE_NAMES := {
	&"physique": "体魄", &"dexterity": "灵巧", &"perception": "感知",
	&"insight": "悟性", &"affinity": "亲和",
}

@export var id: StringName
@export var display_name: String
@export var primary_attribute: StringName
@export var secondary_attribute: StringName
@export var experience_per_effort: float = 1.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or display_name.strip_edges().is_empty():
		errors.append("技能需要 id 和名称")
	if not ATTRIBUTE_NAMES.has(primary_attribute) or not ATTRIBUTE_NAMES.has(secondary_attribute):
		errors.append("技能 %s 引用了未知属性" % id)
	if experience_per_effort <= 0.0:
		errors.append("技能 %s 的每次练习经验必须大于零" % id)
	return errors
