extends Node

signal changed

const SAVE_PATH := "user://display_settings.cfg"
const WINDOW_SIZES := [Vector2i(960, 540), Vector2i(1280, 768), Vector2i(1600, 900), Vector2i(1920, 1080)]
const UI_SCALES := [0.75, 1.0, 1.25, 1.5]

var windowed_size := Vector2i(1600, 900)
var fullscreen := false
var ui_scale := 1.0
var _changing_window := false
var _save_timer: Timer


func _ready() -> void:
	var available := available_sizes()
	windowed_size = Vector2i(1600, 900) if Vector2i(1600, 900) in available else available.back()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var saved_size := Vector2i(int(config.get_value("display", "width", windowed_size.x)),
			int(config.get_value("display", "height", windowed_size.y)))
		var usable := _usable_size()
		if saved_size.x >= 960 and saved_size.y >= 540 and saved_size.x <= usable.x and saved_size.y <= usable.y:
			windowed_size = saved_size
		var saved_scale: float = float(config.get_value("display", "ui_scale", 1.0))
		if saved_scale in UI_SCALES:
			ui_scale = saved_scale
		fullscreen = bool(config.get_value("display", "fullscreen", false))
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)
	if not Engine.is_embedded_in_editor():
		_apply_window()
	get_window().size_changed.connect(_on_window_resized)


func available_sizes() -> Array[Vector2i]:
	var usable := _usable_size()
	var result: Array[Vector2i] = []
	for preset in WINDOW_SIZES:
		if preset.x <= usable.x and preset.y <= usable.y:
			result.append(preset)
	if result.is_empty():
		result.append(usable)
	return result


func _usable_size() -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect().size
	return usable if usable.x > 0 and usable.y > 0 else Vector2i(1600, 900)


func set_fullscreen(value: bool) -> void:
	if Engine.is_embedded_in_editor() or fullscreen == value:
		return
	fullscreen = value
	_apply_window()
	_save()
	changed.emit()


func set_windowed_size(value: Vector2i) -> void:
	if Engine.is_embedded_in_editor():
		return
	var usable := _usable_size()
	if value.x < mini(960, usable.x) or value.y < mini(540, usable.y) or value.x > usable.x or value.y > usable.y:
		return
	if windowed_size == value:
		return
	windowed_size = value
	if not fullscreen:
		_apply_window()
	_save()
	changed.emit()


func set_ui_scale(value: float) -> void:
	if value not in UI_SCALES or is_equal_approx(ui_scale, value):
		return
	ui_scale = value
	_save()
	changed.emit()


func _apply_window() -> void:
	_changing_window = true
	var window := get_window()
	window.borderless = false
	var usable := _usable_size()
	window.min_size = Vector2i(mini(960, usable.x), mini(540, usable.y))
	var use_fullscreen := fullscreen and DisplayServer.get_name() != "headless"
	window.mode = Window.MODE_FULLSCREEN if use_fullscreen else Window.MODE_WINDOWED
	if not use_fullscreen:
		window.size = windowed_size
		if DisplayServer.get_name() != "headless":
			var screen_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
			window.position = screen_rect.position + Vector2i((Vector2(screen_rect.size - window.size) * 0.5).round())
	_changing_window = false


func _on_window_resized() -> void:
	if Engine.is_embedded_in_editor() or _changing_window or fullscreen:
		return
	windowed_size = get_window().size
	_save_timer.start()
	changed.emit()


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "width", windowed_size.x)
	config.set_value("display", "height", windowed_size.y)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "ui_scale", ui_scale)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("显示设置保存失败：%s" % error_string(error))
