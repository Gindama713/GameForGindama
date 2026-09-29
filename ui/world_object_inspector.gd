class_name WorldObjectInspector
extends PanelContainer

## 查询世界状态，不从 Sprite 推断地物；场景内连接本地 Field。
@onready var _field: WorldObjectField = get_parent().get_parent() as WorldObjectField
var _selected: WorldObject
var _details: Label
var _action: Button
var _hint: Label
@onready var _interaction: WorldObjectInteraction = _field.get_node("Interaction") as WorldObjectInteraction


func _ready() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Label.new()
	title.text = "地物检视"
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = Button.new()
	close.text = "关闭"
	close.add_theme_font_size_override("font_size", 11)
	close.pressed.connect(_close)
	header.add_child(close)
	_details = Label.new()
	_details.add_theme_font_size_override("font_size", 11)
	column.add_child(_details)
	_action = Button.new()
	_action.add_theme_font_size_override("font_size", 11)
	_action.pressed.connect(_gather_selected)
	column.add_child(_action)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	column.add_child(_hint)
	_interaction.inspect_requested.connect(inspect)
	_field.object_changed.connect(_on_changed)
	_field.object_removed.connect(_on_removed)
	EventBus.creature_clicked.connect(_on_creature_clicked)
	get_viewport().size_changed.connect(_layout)
	_layout()
	hide()


func _layout() -> void:
	position = Vector2(minf(344.0, maxf(8.0, get_viewport_rect().size.x - 220.0)), 80.0)
	custom_minimum_size.x = 200.0


func _unhandled_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var world_position: Vector2 = get_viewport().canvas_transform.affine_inverse() * mouse.position
	var object: WorldObject = _field.object_at_world_position(world_position)
	var coord: Vector2i = object.coord if object != null else GridManager.grid.world_to_grid(world_position)
	var cell: Grid.Cell = GridManager.grid.get_cell(coord)
	# 同格生物或尸体的点击交给原有检视入口，避免节点处理顺序决定选中谁。
	if cell != null and (cell.content != null or cell.corpse != null):
		return
	if inspect(coord):
		get_viewport().set_input_as_handled()
	else:
		_close()


func inspect(coord: Vector2i) -> bool:
	_selected = _field.object_at(coord)
	if _selected == null:
		_close()
		return false
	_refresh()
	show()
	return true


func _refresh() -> void:
	_details.text = "%s  #%d\n位置 (%d, %d)\n完整度 %d / %d\n%s" % [
		_selected.definition.display_name, _selected.id, _selected.coord.x, _selected.coord.y,
		_selected.integrity, _selected.definition.max_integrity,
		"阻挡通行" if _selected.blocks_movement() else "可穿过"]

	_refresh_action()


func _process(_delta: float) -> void:
	if visible and _selected != null:
		_refresh_action()


func _refresh_action() -> void:
	_action.visible = _selected.definition.gather_item != null
	_hint.visible = _action.visible
	if _action.visible:
		var reason: String = _interaction.gather_reason(_selected.coord)
		_action.text = _selected.definition.gather_action
		_action.disabled = not reason.is_empty()
		_hint.text = reason if not reason.is_empty() else "左键或 E 收集"


func _gather_selected() -> void:
	if _selected != null:
		_interaction.gather(_selected.coord)


func _on_changed(object: WorldObject) -> void:
	if object == _selected:
		_refresh()


func _on_removed(object: WorldObject) -> void:
	if object == _selected:
		_close()


func _on_creature_clicked(_creature: Node) -> void:
	_close()


func _close() -> void:
	_selected = null
	hide()
