class_name BackpackView
extends VBoxContainer

const FONT_SIZE := 13

var _inventory: Inventory
var _summary: Label
var _hands: VBoxContainer
var _bag: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", FONT_SIZE)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_summary)
	_hands = VBoxContainer.new()
	add_child(_hands)
	_bag = VBoxContainer.new()
	add_child(_bag)


func bind(inventory: Inventory) -> void:
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	_inventory = inventory
	if _inventory != null:
		_inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for root in [_hands, _bag]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
	if _inventory == null:
		_summary.text = "没有背包"
		return
	var bag_slots: Array[ItemDef] = _inventory.bag_slots()
	_summary.text = "背包 %d / %d" % [_inventory.bag_used_count(), bag_slots.size()]
	if bag_slots.is_empty():
		_bag.add_child(_small("尚无背包空间"))
	var hands: Array[Dictionary] = _inventory.hand_slots()
	for i in hands.size():
		var part: BodyPart = hands[i]["part"] as BodyPart
		var item: ItemDef = hands[i]["item"] as ItemDef
		var hand_label: String = part.def.grasp_label if not part.def.grasp_label.is_empty() else part.def.label
		_hands.add_child(_row(hand_label, item, "收起", _inventory.can_stow_hand(i),
			_on_stow.bind(i)))
	for i in bag_slots.size():
		_bag.add_child(_row("%d" % (i + 1), bag_slots[i], "取出", _inventory.can_take_from_bag(i),
			_on_take.bind(i)))


func _on_stow(index: int) -> void:
	_inventory.stow_hand(index)


func _on_take(index: int) -> void:
	_inventory.take_from_bag(index)


func _row(slot_label: String, item: ItemDef, action: String, enabled: bool, callback: Callable) -> Control:
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = item.icon if item != null else null
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var label := _small("%s %s" % [slot_label, item.display_name if item != null else "空"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.tooltip_text = item.display_name if item != null else "空"
	row.add_child(label)
	var button := Button.new()
	button.text = action
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(callback)
	row.add_child(button)
	return row


func _small(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
