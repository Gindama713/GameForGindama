extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node2D = load("res://main.tscn").instantiate() as Node2D
	add_child(game)
	await get_tree().process_frame
	var feed: Control = game.get_node("UI/Canvas/SensationFeed") as Control
	var hud: Control = game.get_node("UI/Canvas/PlayerHud") as Control
	var player: Creature = game.get("player") as Creature
	if not _require(feed != null and feed.visible and player != null, "感受面板没有绑定玩家"):
		return
	var area: Rect2 = feed.get_global_rect()
	var hud_area: Rect2 = hud.get_global_rect()
	if not _require(area.position.x >= 0.0 and area.end.x <= get_viewport().get_visible_rect().size.x
			and area.position.y >= 0.0 and not area.intersects(hud_area), "底部面板越界或挡住 HUD"):
		return
	var entries: Array = feed.get("_entries")
	if not _require(entries.is_empty(), "开局产生了虚构的感受"):
		return
	var gap: float = feed.get("_ambient_left")
	if not _require(gap >= 6.0 and gap <= 10.0, "日常感受间隔不在 6～10 秒内"):
		return
	var needs: Needs = player.get_component(Needs) as Needs
	var fatigue: Need = needs.need_by_id(NeedIds.FATIGUE)
	fatigue.value = fatigue.def.max_value * 0.65
	feed.call("_sample_levels")
	if not _require(entries.size() == 1 and String(entries.back()["text"]).contains("累"), "疲劳跨档没有提示"):
		return
	feed.call("_sample_levels")
	if not _require(entries.size() == 1, "同一档疲劳重复提示"):
		return
	fatigue.value = fatigue.def.max_value * 0.25
	feed.call("_sample_levels")
	if not _require(entries.size() == 2, "严重疲劳没有升级提示"):
		return
	var passer: Creature = Creature.new()
	passer.coord = player.coord + Vector2i(10, 0)
	feed.call("_on_creature_moved", passer)
	if not _require(entries.size() == 2, "远处移动被说成身边脚步"):
		return
	passer.coord = player.coord + Vector2i(1, 0)
	feed.call("_on_creature_moved", passer)
	if not _require(entries.size() == 2, "看得见的贴身生物仍被说成附近脚步"):
		return
	TimeSystem.elapsed = float(TimeSystem.NIGHT_START_HOUR * 60)
	feed.call("_on_creature_moved", passer)
	if not _require(entries.size() == 2, "夜间贴身生物仍被说成附近脚步"):
		return
	passer.coord = player.coord + Vector2i(3, 0)
	feed.call("_on_creature_moved", passer)
	if not _require(entries.size() == 3 and String(entries.back()["text"]).contains("脚步"), "夜间稍远的移动没有提示"):
		return
	feed.call("_on_creature_moved", passer)
	if not _require(entries.size() == 3, "连续脚步刷屏"):
		return
	var body: Body = player.get_component(Body) as Body
	var part: BodyPart = body.parts[0]
	body.hurt(part, 5.0)
	if not _require(entries.size() == 4 and String(entries.back()["text"]).contains(part.def.label), "受伤提示没有读取真实部位"):
		return
	var sleep: Sleep = player.get_component(Sleep) as Sleep
	if not _require(sleep.start(), "无法开始测试睡眠"):
		return
	TimeSystem.elapsed = float(TimeSystem.NIGHT_START_HOUR * 60)
	sleep.wake_up("附近有动静", Sleep.Wake.DISTURBED)
	if not _require(entries.size() == 5 and String(entries.back()["text"]).contains("黑暗中的脚步声"), "夜间惊醒提示没有响应实际唤醒"):
		return
	feed.call("_on_creature_moved", passer)
	if not _require(entries.size() == 5, "惊醒后同一阵脚步重复提示"):
		return
	passer.free()
	feed.call("_on_history_toggled", true)
	var history: RichTextLabel = feed.get("_history") as RichTextLabel
	if not _require(feed.get_global_rect().size.y > area.size.y and history.text.contains("第"), "历史记录没有向上展开或缺少日期"):
		return
	fatigue.value = fatigue.def.max_value * 0.8
	feed.set("_last_urgent_ms", -100000)
	var last_by_key: Dictionary = feed.get("_last_by_key")
	last_by_key.erase("ambient:fatigue")
	feed.call("_ambient_note")
	if not _require(entries.size() == 6 and String(entries.back()["text"]).contains("累"), "日常提示没有基于真实状态"):
		return
	if not _require(not feed.call("_maybe_routine", "草叶响了。", "routine:check", 0.0, 45.0)
			and entries.size() == 6, "零概率的日常感受仍然出现"):
		return
	feed.set("_last_routine_ms", -100000)
	if not _require(feed.call("_maybe_routine", "草叶响了。", "routine:check", 1.0, 45.0)
			and entries.size() == 7, "日常感受没有触发"):
		return
	if not _require(not feed.call("_maybe_routine", "草叶又响了。", "routine:check", 1.0, 45.0)
			and entries.size() == 7, "日常感受没有冷却"):
		return
	print("sensation_smoke: PASS area=", area, " hud=", hud_area)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("sensation_smoke: " + message)
		get_tree().quit(1)
	return ok
