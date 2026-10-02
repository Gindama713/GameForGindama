extends PanelContainer

signal drop_requested(hand_index: int)

const EDGE := 8.0
const ICON_SIZE := 48.0

var _inventory: Inventory
var _list: VBoxContainer
var _frames: Array[Dictionary] = []
var _selected_hand: int = -1


func _ready() -> void:
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	EventBus.player_spawned.connect(_bind)
	get_parent().resized.connect(_layout)
	resized.connect(_layout)
	var minimap: Control = get_parent().get_node_or_null("Minimap") as Control
	if minimap != null:
		minimap.resized.connect(_layout)
	hide()


func _layout() -> void:
	var canvas: Control = get_parent() as Control
	var minimap: Control = canvas.get_node_or_null("Minimap") as Control
	var top: float = minimap.position.y + minimap.size.y + EDGE if minimap != null else EDGE
	position = Vector2(canvas.size.x - size.x - EDGE,
		minf(top, maxf(EDGE, canvas.size.y - size.y - EDGE)))


func _bind(node: Node) -> void:
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	var actor: Creature = node as Creature
	_inventory = actor.get_component(Inventory) as Inventory if actor != null else null
	visible = _inventory != null
	_selected_hand = -1
	_rebuild()
	if _inventory != null:
		_inventory.changed.connect(_refresh)
	_refresh()
	_layout.call_deferred()


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_frames.clear()
	if _inventory == null:
		return
	var slots: Array[Dictionary] = _inventory.hand_slots()
	for i in slots.size():
		var frame := PanelContainer.new()
		frame.custom_minimum_size.x = 60.0
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.gui_input.connect(_on_frame_input.bind(i))
		_list.add_child(frame)
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(column)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2.ONE * ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(icon)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
		var drop := Button.new()
		drop.text = "放下"
		drop.add_theme_font_size_override("font_size", 11)
		drop.pressed.connect(_request_drop.bind(i))
		column.add_child(drop)
		_frames.append({"frame": frame, "icon": icon, "label": label, "drop": drop})


func _refresh() -> void:
	if _inventory == null:
		return
	var slots: Array[Dictionary] = _inventory.hand_slots()
	for i in mini(slots.size(), _frames.size()):
		var part: BodyPart = slots[i]["part"] as BodyPart
		var item: ItemDef = slots[i]["item"] as ItemDef
		var frame: PanelContainer = _frames[i]["frame"]
		var icon: TextureRect = _frames[i]["icon"]
		var label: Label = _frames[i]["label"]
		var drop: Button = _frames[i]["drop"]
		icon.texture = item.icon if item != null else part.def.grasp_texture
		icon.flip_h = part.def.grasp_flip_h
		label.text = part.def.grasp_label if not part.def.grasp_label.is_empty() else part.def.label
		frame.tooltip_text = "%s · %s\n点击查看操作" % [label.text, item.display_name if item != null else "空手"]
		drop.visible = i == _selected_hand and item != null
	_layout.call_deferred()


func _on_frame_input(event: InputEvent, hand_index: int) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_selected_hand = -1 if _selected_hand == hand_index else hand_index
	_refresh()
	accept_event()


func _request_drop(hand_index: int) -> void:
	_selected_hand = -1
	drop_requested.emit(hand_index)
	_refresh()
