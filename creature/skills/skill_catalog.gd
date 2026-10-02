class_name SkillCatalog
extends Resource

@export var skills: Array[SkillDef] = []


func find(id: StringName) -> SkillDef:
	for skill in skills:
		if skill != null and skill.id == id:
			return skill
	return null


func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for skill in skills:
		if skill == null:
			errors.append("技能表含空项")
			continue
		errors.append_array(skill.validate())
		if seen.has(skill.id):
			errors.append("技能 id 重复：%s" % skill.id)
		seen[skill.id] = true
	if skills.is_empty():
		errors.append("技能表不能为空")
	return errors
