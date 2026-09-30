extends Node

var _saved_size := Vector2i.ZERO
var _saved_scale := 1.0
var _saved_fullscreen := false


func _ready() -> void:
	_run.call_deferred()


func _exit_tree() -> void:
	if _saved_size == Vector2i.ZERO:
		return
	DisplaySettings.set_ui_scale(_saved_scale)
	DisplaySettings.set_windowed_size(_saved_size)
	DisplaySettings.set_fullscreen(_saved_fullscreen)


func _run() -> void:
	var game := load("res://main.tscn").instantiate() as Node2D
	add_child(game)
	await get_tree().process_frame
	var ui := game.get_node("UI") as CanvasLayer
	var ui_canvas := game.get_node("UI/Canvas") as Control
	var object_ui := game.get_node("WorldObjects/UI") as CanvasLayer
	var object_canvas := game.get_node("WorldObjects/UI/Canvas") as Control
	var settings_ui := game.get_node("SettingsUI") as CanvasLayer
	var settings_canvas := game.get_node("SettingsUI/Canvas") as Control
	var menu := game.get_node("SettingsUI/Canvas/SettingsMenu") as Control
	var night := game.get_node("Effects/NightOverlay") as Control
	var camera := game.get_node("Camera2D") as Camera2D
	var original_zoom := camera.zoom
	var feed := game.get_node("UI/Canvas/SensationFeed") as Control
	var hud := game.get_node("UI/Canvas/PlayerHud") as Control
	var minimap := game.get_node("UI/Canvas/Minimap") as Control
	var inventory := game.get_node("UI/Canvas/Inventory") as Control
	var player_panel := game.get_node("UI/Canvas/PlayerPanel") as Control
	var creature_inspector := game.get_node("UI/Canvas/CreatureInspector") as Control
	_saved_size = DisplaySettings.windowed_size
	_saved_scale = DisplaySettings.ui_scale
	_saved_fullscreen = DisplaySettings.fullscreen
	DisplaySettings.set_fullscreen(false)
	for preset in DisplaySettings.available_sizes():
		for factor in DisplaySettings.UI_SCALES:
			DisplaySettings.set_windowed_size(preset)
			DisplaySettings.set_ui_scale(factor)
			await get_tree().process_frame
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			var expected: Vector2 = viewport_size / float(factor)
			if not _require(ui.scale.is_equal_approx(Vector2.ONE * float(factor))
					and object_ui.scale.is_equal_approx(ui.scale)
					and settings_ui.scale.is_equal_approx(ui.scale)
					and ui_canvas.size.is_equal_approx(expected)
					and object_canvas.size.is_equal_approx(expected)
					and settings_canvas.size.is_equal_approx(expected), "UI 层缩放或虚拟尺寸不同步"):
				return
			if not _require(night.size.is_equal_approx(viewport_size), "夜晚遮罩没有铺满物理窗口"):
				return
			if not _require(camera.zoom.is_equal_approx(original_zoom), "调整窗口或 UI 改变了世界缩放"):
				return
			for control in [feed, hud, minimap, inventory]:
				var rect: Rect2 = control.get_global_rect()
				if not _require(rect.position.x >= -1 and rect.position.y >= -1
						and rect.end.x <= expected.x + 1 and rect.end.y <= expected.y + 1,
						"UI 越界：%s %s @ %s / %s" % [control.name, rect, preset, factor]):
					return
			if not _require(not feed.get_global_rect().intersects(inventory.get_global_rect()),
					"感受栏与物品栏重叠：%s @ %s" % [preset, factor]):
				return
			var panel := player_panel.get("_panel") as Control
			if not _require(panel.size.y <= expected.y - 15.0, "角色档案高度超出屏幕"):
				return
			print("display layout: ", preset, " ui=", factor, " feed=", feed.get_global_rect(), " inventory=", inventory.get_global_rect())
			if preset == Vector2i(960, 540) and factor == 1.5:
				var pig := game.get_node("Creatures").get_child(0) as Creature
				EventBus.creature_clicked.emit(pig)
				await get_tree().process_frame
				if not _require(creature_inspector.get_global_rect().end.y <= expected.y,
						"生物检视越界：%s / %s" % [creature_inspector.get_global_rect(), expected]):
					return
				creature_inspector.call("_on_open_tree")
				var tree := creature_inspector.get("_tree") as FamilyTree
				if not _require(tree != null and tree.get_global_rect().end.y <= expected.y,
						"族谱窗口越界"):
					return
				tree.close()
				creature_inspector.hide()
	var button := menu.get_child(0) as Button
	var click_position := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = click_position
	get_viewport().push_input(click, true)
	click.pressed = false
	get_viewport().push_input(click, true)
	await get_tree().process_frame
	if not _require((menu.get("_shade") as ColorRect).visible, "鼠标点击设置按钮没有打开面板"):
		return
	(menu.get("_mode") as OptionButton).item_selected.emit(1)
	if not _require(DisplaySettings.fullscreen and (menu.get("_resolution") as OptionButton).disabled,
			"全屏选项没有生效"):
		return
	(menu.get("_mode") as OptionButton).item_selected.emit(0)
	(menu.get("_ui_scale") as OptionButton).item_selected.emit(2)
	if not _require(is_equal_approx(DisplaySettings.ui_scale, 1.25), "UI 倍率选项没有生效"):
		return
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().process_frame
	if not _require(not (menu.get("_shade") as ColorRect).visible, "Esc 没有关闭设置面板"):
		return
	DisplaySettings.set_ui_scale(_saved_scale)
	DisplaySettings.set_windowed_size(_saved_size)
	DisplaySettings.set_fullscreen(_saved_fullscreen)
	await get_tree().create_timer(0.6).timeout
	var stored := ConfigFile.new()
	if not _require(stored.load(DisplaySettings.SAVE_PATH) == OK
			and int(stored.get_value("display", "width", 0)) == _saved_size.x
			and int(stored.get_value("display", "height", 0)) == _saved_size.y
			and bool(stored.get_value("display", "fullscreen", not _saved_fullscreen)) == _saved_fullscreen
			and is_equal_approx(float(stored.get_value("display", "ui_scale", 0.0)), _saved_scale),
			"显示设置没有保存并恢复"):
		return
	print("display_settings_smoke: PASS")
	get_tree().quit()


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("display_settings_smoke: " + message)
		get_tree().quit(1)
	return ok
