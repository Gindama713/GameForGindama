extends PanelContainer

signal drop_requested(hand_index: int)

var _inventory: Inventory
var _toggle: Button
var _list: VBoxContainer


func _ready() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	_toggle = Button.new()
	_toggle.add_theme_font_size_override("font_size", 12)
	_toggle.toggle_mode = true
	_toggle.toggled.connect(_on_toggled)
	column.add_child(_toggle)
	_list = VBoxContainer.new()
	column.add_child(_list)
	_toggle.button_pressed = true
	var hint: Label = Label.new()
	hint.text = "左键 / E 拾取 · 一只手一件"
	hint.add_theme_font_size_override("font_size", 11)
	column.add_child(hint)
	EventBus.player_spawned.connect(_bind)
	get_viewport().size_changed.connect(_layout)
	_layout()
	hide()


func _layout() -> void:
	position = Vector2(maxf(8.0, get_viewport_rect().size.x - 228.0), 144.0)
	custom_minimum_size.x = 220.0


func _bind(node: Node) -> void:
	if _inventory != null:
		_inventory.changed.disconnect(_refresh)
	var actor: Creature = node as Creature
	_inventory = actor.get_component(Inventory) as Inventory if actor != null else null
	visible = _inventory != null
	if _inventory != null:
		_inventory.changed.connect(_refresh)
	_refresh()


func _on_toggled(open: bool) -> void:
	_list.visible = open


func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _inventory == null:
		return
	var slots: Array[Dictionary] = _inventory.hand_slots()
	for i in slots.size():
		var item: ItemDef = slots[i]["item"] as ItemDef
		var part: BodyPart = slots[i]["part"] as BodyPart
		var row: HBoxContainer = HBoxContainer.new()
		_list.add_child(row)
		var icon: TextureRect = TextureRect.new()
		icon.texture = item.icon if item != null else part.def.grasp_texture
		icon.flip_h = part.def.grasp_flip_h
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		row.add_child(icon)
		var label: Label = Label.new()
		var hand_name: String = part.def.grasp_label if not part.def.grasp_label.is_empty() else part.def.label
		label.text = "%s · %s" % [hand_name, item.display_name if item != null else "空手"]
		label.tooltip_text = part.def.label
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 11)
		row.add_child(label)
		var drop: Button = Button.new()
		drop.text = "放下"
		drop.add_theme_font_size_override("font_size", 11)
		drop.disabled = item == null
		drop.pressed.connect(_request_drop.bind(i))
		row.add_child(drop)
	_toggle.text = "手中物品 · %d / %d" % [_inventory.used_count(), slots.size()]


func _request_drop(hand_index: int) -> void:
	drop_requested.emit(hand_index)
