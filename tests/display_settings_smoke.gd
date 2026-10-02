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
	var inventory := game.get_node("UI/Canvas/HandsHud") as Control
	var player_panel := game.get_node("UI/Canvas/PlayerPanel") as Control
	var drawer_buttons: Array = player_panel.get("_drawer_buttons")
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
			if not _require(not minimap.get_global_rect().intersects(inventory.get_global_rect()),
					"双手框与小地图重叠：%s @ %s" % [preset, factor]):
				return
			var panel := player_panel.get("_panel") as Control
			if not _require(panel.size.y <= expected.y - 15.0, "角色档案高度超出屏幕"):
				return
			(drawer_buttons[0] as Button).pressed.emit()
			await get_tree().create_timer(0.24).timeout
			var portrait := player_panel.get("_portrait_box") as Control
			var skills := player_panel.get("_skill_list") as SkillList
			var rail := player_panel.get("_drawer_rail") as Control
			var profile_frame := player_panel.get("_profile_background") as Panel
			var skill_clip: Control = (player_panel.get("_drawer_clips") as Array)[0] as Control
			var skill_background := skill_clip.get_child(0) as ColorRect
			var skill_title: Label = ((player_panel.get("_drawer_pages") as Array)[0] as Control).get_child(0) as Label
			if not _require(skills.get_global_rect().position.x > portrait.get_global_rect().end.x
					and panel.size.x <= expected.x - 16.0
					and skills.get_global_rect().end.x <= panel.get_global_rect().end.x + 1.0
					and skills.get_global_rect().position.y < panel.get_global_rect().end.y
					and rail.get_global_rect().position.x < skills.get_global_rect().position.x
					and rail.get_global_rect().end.x <= panel.get_global_rect().end.x + 1.0,
					"技能或箭头越界：档案=%s 技能=%s 箭头=%s 面板=%s @ %s/%s" % [
						portrait.get_global_rect(), skills.get_global_rect(), rail.get_global_rect(),
						panel.get_global_rect(), preset, factor]):
				return
			if not _require((drawer_buttons[0] as Button).flat and (drawer_buttons[1] as Button).flat
					and (drawer_buttons[2] as Button).flat
					and absf(rail.get_global_rect().get_center().y - panel.get_global_rect().get_center().y) < 24.0
					and profile_frame.get_global_rect().encloses(rail.get_global_rect()),
					"箭头有单独边框，或没有放进人物资料框"):
				return
			if not _require(skill_clip.size.x >= 259.0 and skill_background.color == Color.BLACK
					and skill_background.size.is_equal_approx(skill_clip.size)
					and skill_title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
					and skill_title.get_theme_font_size("font_size") >= 15
					and skills.font_size >= 13 and skills.center_rows,
					"抽屉宽度、无边框背景或居中文字没有生效"):
				return
			if not _require((skills.get("_grid") as GridContainer).get_child_count() == 12,
					"右侧技能列没有完整显示共享技能表"):
				return
			for node in skills.find_children("*", "Label", true, false):
				if not _require(not (node as Label).text.contains("先天"), "玩家界面泄露了先天天赋"):
					return
			(drawer_buttons[0] as Button).pressed.emit()
			await get_tree().create_timer(0.24).timeout
			var clips: Array = player_panel.get("_drawer_clips")
			if not _require((clips[0] as Control).size.x < 1.0, "技能抽屉没有收回"):
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
	DisplaySettings.set_windowed_size(DisplaySettings.available_sizes()[0])
	DisplaySettings.set_ui_scale(1.5)
	await get_tree().process_frame
	(drawer_buttons[0] as Button).pressed.emit()
	await get_tree().create_timer(0.24).timeout
	var bag_arrow := drawer_buttons[1] as Button
	var arrow_click := InputEventMouseButton.new()
	arrow_click.button_index = MOUSE_BUTTON_LEFT
	arrow_click.pressed = true
	arrow_click.position = bag_arrow.get_global_transform_with_canvas() * (bag_arrow.size * 0.5)
	get_viewport().push_input(arrow_click, true)
	arrow_click.pressed = false
	get_viewport().push_input(arrow_click, true)
	await get_tree().create_timer(0.24).timeout
	var pages: Array = player_panel.get("_drawer_pages")
	if not _require((pages[0] as Control).visible and (pages[1] as Control).visible,
			"打开背包时技能抽屉被关掉：箭头=%s 面板=%s 双手=%s 状态=%s/%s" % [
				bag_arrow.get_global_rect(), (player_panel.get("_panel") as Control).get_global_rect(),
				inventory.get_global_rect(), (pages[0] as Control).visible, (pages[1] as Control).visible]):
		return
	var craft_arrow := drawer_buttons[2] as Button
	arrow_click.pressed = true
	arrow_click.position = craft_arrow.get_global_transform_with_canvas() * (craft_arrow.size * 0.5)
	get_viewport().push_input(arrow_click, true)
	arrow_click.pressed = false
	get_viewport().push_input(arrow_click, true)
	await get_tree().create_timer(0.24).timeout
	var final_panel := player_panel.get("_panel") as Control
	if not _require((pages[0] as Control).visible and (pages[1] as Control).visible
			and (pages[2] as Control).visible
			and (drawer_buttons[2] as Button).get_global_rect().end.x <= final_panel.get_global_rect().end.x + 1.0,
			"三个抽屉没有同时打开，或剩余箭头不可见：状态=%s/%s/%s 箭头=%s 面板=%s 滚动=%s" % [
				(pages[0] as Control).visible, (pages[1] as Control).visible, (pages[2] as Control).visible,
				craft_arrow.get_global_rect(), final_panel.get_global_rect(),
				(player_panel.get("_scroll") as ScrollContainer).scroll_horizontal]):
		return
	for button in drawer_buttons:
		(button as Button).pressed.emit()
	await get_tree().create_timer(0.24).timeout
	if not _require(not (final_panel is PanelContainer), "抽屉区域仍被整块面板边框包住"):
		return
	var close_button := player_panel.get("_close_btn") as Button
	var close_click := InputEventMouseButton.new()
	close_click.button_index = MOUSE_BUTTON_LEFT
	close_click.pressed = true
	close_click.position = close_button.get_global_transform_with_canvas() * (close_button.size * 0.5)
	get_viewport().push_input(close_click, true)
	close_click.pressed = false
	get_viewport().push_input(close_click, true)
	await get_tree().create_timer(0.3).timeout
	if not _require(not final_panel.visible, "鼠标点击人物资料关闭按钮没有收起面板"):
		return
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().process_frame
	if not _require((menu.get("_shade") as ColorRect).visible, "Esc 没有打开设置面板"):
		return
	var sizes := DisplaySettings.available_sizes()
	if sizes.size() > 1:
		var next_index := 0 if DisplaySettings.windowed_size != sizes[0] else 1
		(menu.get("_resolution") as OptionButton).item_selected.emit(next_index)
		await get_tree().process_frame
		if not _require(DisplaySettings.windowed_size == sizes[next_index]
				and get_window().size == sizes[next_index], "窗口大小选项没有调整实际窗口"):
			return
	(menu.get("_mode") as OptionButton).item_selected.emit(1)
	if not _require(DisplaySettings.fullscreen and (menu.get("_resolution") as OptionButton).disabled,
			"全屏选项没有生效"):
		return
	(menu.get("_mode") as OptionButton).item_selected.emit(0)
	(menu.get("_ui_scale") as OptionButton).item_selected.emit(2)
	if not _require(is_equal_approx(DisplaySettings.ui_scale, 1.25), "UI 倍率选项没有生效"):
		return
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
