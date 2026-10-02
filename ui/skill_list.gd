class_name SkillList
extends VBoxContainer

var columns: int = 2
var bar_segments: int = 10
var font_size: int = 11
var center_rows: bool = false
var _skills: Skills
var _grid: GridContainer
var _rows: Dictionary = {}


func _ready() -> void:
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 6 if center_rows else 2)
	if center_rows:
		_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_grid)


func bind(skills: Skills) -> void:
	_skills = skills
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_rows.clear()
	visible = skills != null
	if skills == null:
		return
	for definition: SkillDef in skills.creature.def.skill_catalog.skills:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", font_size)
		if center_rows:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(label)
		var bar := PixelBar.new()
		bar.segments = bar_segments
		bar.cell = Vector2(8, 4)
		bar.gap = 1
		row.add_child(bar)
		_grid.add_child(row)
		_rows[definition.id] = {"root": row, "label": label, "bar": bar, "definition": definition}
	refresh()


func refresh() -> void:
	if _skills == null:
		return
	for id: StringName in _rows:
		var row: Dictionary = _rows[id]
		var definition: SkillDef = row["definition"]
		var label: Label = row["label"]
		label.text = "%s %d · %s" % [definition.display_name, _skills.level(id),
			"满级" if _skills.level(id) == Skills.MAX_LEVEL else "%.1f/%.1f" % [
				_skills.experience(id), _skills.experience_to_next(id)]]
		var bar: PixelBar = row["bar"]
		bar.set_ratio(_skills.progress_ratio(id))
		var tip := "%s Lv.%d  经验 %.1f/%.1f" % [definition.display_name,
			_skills.level(id), _skills.experience(id), _skills.experience_to_next(id)]
		row["root"].tooltip_text = tip
		label.tooltip_text = tip
