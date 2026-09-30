extends Control

var _panel: PanelContainer
var _shade: ColorRect
var _mode: OptionButton
var _resolution: OptionButton
var _ui_scale: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var open_button := Button.new()
	open_button.text = "设置"
	open_button.tooltip_text = "显示设置（Esc）"
	open_button.set_anchors_preset(PRESET_TOP_RIGHT)
	open_button.offset_left = -84
	open_button.offset_right = -8
	open_button.offset_top = 112
	open_button.offset_bottom = 140
	open_button.pressed.connect(_toggle)
	add_child(open_button)

	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.58)
	_shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_shade.mouse_filter = MOUSE_FILTER_STOP
	add_child(_shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	_shade.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(356, 0)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "显示设置"
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	_mode = _option_row(column, "显示模式")
	_mode.add_item("窗口", 0)
	_mode.add_item("全屏", 1)
	_mode.item_selected.connect(func(index: int) -> void: DisplaySettings.set_fullscreen(index == 1))
	_resolution = _option_row(column, "窗口大小")
	_resolution.item_selected.connect(_on_resolution_selected)
	_ui_scale = _option_row(column, "UI 大小")
	for value in DisplaySettings.UI_SCALES:
		_ui_scale.add_item("%d%%" % int(value * 100))
	_ui_scale.item_selected.connect(func(index: int) -> void: DisplaySettings.set_ui_scale(DisplaySettings.UI_SCALES[index]))
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_toggle)
	column.add_child(close)
	_shade.hide()
	DisplaySettings.changed.connect(_refresh)
	_refresh()


func _option_row(parent: VBoxContainer, title: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 88
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _refresh() -> void:
	_mode.select(1 if DisplaySettings.fullscreen else 0)
	_resolution.disabled = DisplaySettings.fullscreen
	_resolution.clear()
	var sizes := DisplaySettings.available_sizes()
	for preset in sizes:
		_resolution.add_item("%d × %d" % [preset.x, preset.y])
	var selected := sizes.find(DisplaySettings.windowed_size)
	if selected < 0:
		_resolution.add_item("%d × %d（当前）" % [DisplaySettings.windowed_size.x, DisplaySettings.windowed_size.y])
		selected = _resolution.item_count - 1
	_resolution.select(selected)
	_ui_scale.select(DisplaySettings.UI_SCALES.find(DisplaySettings.ui_scale))


func _on_resolution_selected(index: int) -> void:
	var sizes := DisplaySettings.available_sizes()
	if index < sizes.size():
		DisplaySettings.set_windowed_size(sizes[index])


func _toggle() -> void:
	_shade.visible = not _shade.visible
	if _shade.visible:
		_mode.grab_focus()
	else:
		get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_toggle()
		get_viewport().set_input_as_handled()
