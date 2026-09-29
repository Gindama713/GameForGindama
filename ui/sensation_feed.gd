extends Control

## 玩家感受：事件立即出现；平静时每 6～10 秒从真实状态中挑一句。
## 文案只在这里，生物组件只报告事实。

const QUIET := 0
const NOTICE := 1
const URGENT := 2
const MAX_HISTORY := 100
const FOOTSTEP_RADIUS_SQ := 16
const ROUTINE_GAP_MS := 12000
const NEED_IDS: Array[String] = [NeedIds.FOOD, NeedIds.WATER, NeedIds.WARMTH, NeedIds.FATIGUE]

var _player: Creature
var _needs: Needs
var _body: Body
var _sleep: Sleep
var _inventory: Inventory
var _lines: Array[Label] = []
var _history: RichTextLabel
var _history_button: Button
var _entries: Array[Dictionary] = []
var _last_by_key: Dictionary = {}
var _need_levels: Dictionary = {}
var _part_levels: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ambient_left: float = 0.0
var _sample_left: float = 0.0
var _ambient_turn: int = 0
var _last_urgent_ms: int = -100000
var _last_routine_ms: int = -100000
var _last_player_terrain: StringName = Terrain.UNKNOWN


func _ready() -> void:
	_rng.randomize()
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)
	EventBus.player_spawned.connect(_bind)
	EventBus.creature_moved.connect(_on_creature_moved)
	EventBus.creature_died.connect(_on_creature_died)
	EventBus.creature_removed.connect(_on_creature_removed)
	visible = false


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.04, 0.88)
	style.border_color = Color(0.52, 0.62, 0.59, 0.9)
	style.set_border_width_all(1)
	style.set_content_margin_all(9)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Label.new()
	title.text = "感受"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.76, 0.84, 0.79))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	_history_button = Button.new()
	_history_button.text = "记录"
	_history_button.toggle_mode = true
	_history_button.add_theme_font_size_override("font_size", 11)
	_history_button.toggled.connect(_on_history_toggled)
	header.add_child(_history_button)

	var recent: VBoxContainer = VBoxContainer.new()
	recent.add_theme_constant_override("separation", 1)
	column.add_child(recent)
	for _i in 3:
		var line: Label = Label.new()
		line.custom_minimum_size.y = 18.0
		line.clip_text = true
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_font_size_override("font_size", 11)
		recent.add_child(line)
		_lines.append(line)
	_history = RichTextLabel.new()
	_history.custom_minimum_size.y = 210.0
	_history.visible = false
	_history.selection_enabled = true
	_history.scroll_following = true
	_history.add_theme_font_size_override("normal_font_size", 11)
	column.add_child(_history)
	_refresh_recent(false)


func _layout() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var left: float = minf(260.0, maxf(236.0, screen.x * 0.22))
	var right: float = screen.x - 316.0
	var room: float = right - left
	var width: float = minf(620.0, room) if room >= 360.0 else minf(600.0, screen.x - 16.0)
	var x: float = left + (room - width) * 0.5 if room >= 360.0 else (screen.x - width) * 0.5
	var bottom: float = -8.0 if room >= 360.0 else -140.0
	var height: float = minf(340.0, screen.y * 0.55) if _history != null and _history.visible else 112.0
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = x
	offset_right = x + width
	offset_top = bottom - height
	offset_bottom = bottom


func _on_history_toggled(open: bool) -> void:
	_history.visible = open
	_layout()


func _bind(node: Node) -> void:
	if _inventory != null and _inventory.item_added.is_connected(_on_item_added):
		_inventory.item_added.disconnect(_on_item_added)
		_inventory.item_removed.disconnect(_on_item_removed)
	if _sleep != null and _sleep.woke.is_connected(_on_woke):
		_sleep.woke.disconnect(_on_woke)
	if _body != null and _body.injured.is_connected(_on_injured):
		_body.injured.disconnect(_on_injured)
	_player = node as Creature
	_needs = _player.get_component(Needs) as Needs if _player != null else null
	_body = _player.get_component(Body) as Body if _player != null else null
	_sleep = _player.get_component(Sleep) as Sleep if _player != null else null
	_inventory = _player.get_component(Inventory) as Inventory if _player != null else null
	visible = _player != null
	_entries.clear()
	_last_by_key.clear()
	_need_levels.clear()
	_part_levels.clear()
	_last_routine_ms = -100000
	_last_player_terrain = _player_terrain() if _player != null else Terrain.UNKNOWN
	_ambient_left = _rng.randf_range(6.0, 10.0)
	_sample_left = 0.25
	if _sleep != null:
		_sleep.woke.connect(_on_woke)
	if _body != null:
		_body.injured.connect(_on_injured)
	if _inventory != null:
		_inventory.item_added.connect(_on_item_added)
		_inventory.item_removed.connect(_on_item_removed)
	_snapshot_levels()
	_refresh_recent(false)
	_refresh_history()


func _on_item_added(item: ItemDef, amount: int) -> void:
	_note("你拿起了%s ×%d。" % [item.display_name, amount], NOTICE, "", 0.0)


func _on_item_removed(item: ItemDef, amount: int) -> void:
	_note("你放下了%s ×%d。" % [item.display_name, amount], NOTICE, "", 0.0)


func _on_action_failed(reason: String) -> void:
	_note(reason, NOTICE, "action_failed:" + reason, 2.0)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_alive() or TimeSystem.paused:
		return
	_sample_left -= delta
	if _sample_left <= 0.0:
		_sample_left = 0.25
		_sample_levels()
	if _sleep != null and _sleep.is_sleeping():
		return
	_ambient_left -= delta
	if _ambient_left <= 0.0:
		_ambient_left = _rng.randf_range(6.0, 10.0)
		_ambient_note()


func _snapshot_levels() -> void:
	if _needs != null:
		for id in NEED_IDS:
			var need: Need = _needs.need_by_id(id)
			if need != null:
				_need_levels[id] = _need_level(need.ratio(), 0)
	if _body != null:
		for part in _body.parts:
			_part_levels[part.def.id] = part.severity()


func _sample_levels() -> void:
	if _needs != null:
		for id in NEED_IDS:
			var need: Need = _needs.need_by_id(id)
			if need == null:
				continue
			var previous: int = int(_need_levels.get(id, 0))
			var level: int = _need_level(need.ratio(), previous)
			_need_levels[id] = level
			if level > previous and (_sleep == null or not _sleep.is_sleeping()):
				_note(_need_text(id, level), URGENT if level == 2 else NOTICE, "need:%s:%d" % [id, level], 30.0)
	if _body != null:
		for part in _body.parts:
			var previous: int = int(_part_levels.get(part.def.id, part.severity()))
			var level: int = part.severity()
			_part_levels[part.def.id] = level
			if level > previous:
				_note(_pain_text(part), URGENT if level >= BodyPart.Severity.SEVERE else NOTICE,
					"pain:%s:%d" % [part.def.id, level], 20.0)


func _need_level(ratio: float, previous: int) -> int:
	if previous == 2 and ratio <= 0.38:
		return 2
	if ratio < 0.30:
		return 2
	if previous >= 1 and ratio <= 0.78:
		return 1
	if ratio < 0.70:
		return 1
	return 0


func _need_text(id: String, level: int) -> String:
	match id:
		NeedIds.FATIGUE:
			return "你累得几乎迈不开步。" if level == 2 else "你感觉稍微有一点累。"
		NeedIds.FOOD:
			return "饥饿让你有些发晕。" if level == 2 else "你的肚子开始发空。"
		NeedIds.WATER:
			return "你的喉咙干得难受。" if level == 2 else "你开始觉得口渴。"
		NeedIds.WARMTH:
			return "寒冷正在夺走你的体力。" if level == 2 else "你感到一阵寒意。"
	return ""


func _on_injured(part: BodyPart) -> void:
	if _player == null or not _player.is_alive():
		return
	var level: int = part.severity()
	_part_levels[part.def.id] = level
	_note(_pain_text(part), URGENT if level >= BodyPart.Severity.SEVERE else NOTICE,
		"pain:%s:%d" % [part.def.id, level], 2.0)


func _pain_text(part: BodyPart) -> String:
	var place: String = part.def.label
	match part.severity():
		BodyPart.Severity.DISABLED:
			return "你的%s几乎失去了知觉。" % place
		BodyPart.Severity.SEVERE:
			return "你的%s传来一阵剧痛。" % place
		BodyPart.Severity.MODERATE:
			return "你的%s疼得厉害。" % place
		_:
			return "你的%s隐隐作痛。" % place


func _on_creature_moved(node: Node) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_alive():
		return
	if _sleep != null and _sleep.is_sleeping():
		return
	if node == _player:
		_on_player_moved()
		return
	var other: Creature = node as Creature
	if other == null or not other.is_alive():
		return
	var distance_sq: int = (other.coord - _player.coord).length_squared()
	if distance_sq > FOOTSTEP_RADIUS_SQ:
		return
	# 看得见的贴身生物无需再靠脚步声辨认。
	if not other.is_concealed() and (not TimeSystem.is_night() or distance_sq < 9):
		return
	var message: String = "夜色里传来脚步声。"
	if other.is_concealed():
		message = "草丛里传来细碎的脚步声。"
	_note(message, NOTICE, "footsteps", 45.0)


func _player_terrain() -> StringName:
	var cell: Grid.Cell = GridManager.cell_at(_player.coord.x, _player.coord.y)
	return cell.terrain if cell != null else Terrain.UNKNOWN


func _on_player_moved() -> void:
	var terrain: StringName = _player_terrain()
	var entered_tall_grass: bool = terrain == Terrain.TALL_GRASS and _last_player_terrain != Terrain.TALL_GRASS
	_last_player_terrain = terrain
	if entered_tall_grass and _maybe_routine("你拨开面前的高草。", "routine:enter_tall_grass", 0.25, 45.0):
		return
	var sprint: Sprint = _player.get_component(Sprint) as Sprint
	if sprint != null and sprint.is_running() and _maybe_routine("你跑起来，呼吸渐渐急促。", "routine:run", 0.12, 45.0):
		return
	if GrassField.has_grass(_player.coord):
		_maybe_routine("脚下的草叶轻轻作响。", "routine:grass", 0.08, 45.0)


func _maybe_routine(message: String, key: String, chance: float, cooldown: float) -> bool:
	return _rng.randf() < chance and _note(message, QUIET, key, cooldown)


func _on_woke(kind: int) -> void:
	match kind:
		Sleep.Wake.DISTURBED:
			_last_by_key["footsteps"] = Time.get_ticks_msec()
			_note("你被黑暗中的脚步声惊醒。" if TimeSystem.is_night() else "你被附近的脚步声惊醒。",
				URGENT, "", 0.0)
		Sleep.Wake.RESTED:
			_note("你睡醒了，精神恢复了一些。", QUIET, "", 0.0)
		Sleep.Wake.TOO_LONG:
			_note("你睡了很久，慢慢醒来。", QUIET, "", 0.0)
		Sleep.Wake.MANUAL:
			_note("你主动醒了过来。", QUIET, "", 0.0)


func _on_creature_died(node: Node) -> void:
	if node == _player:
		_note("你倒下了。", URGENT, "", 0.0)


func _on_creature_removed(node: Node) -> void:
	if node == _player:
		_bind(null)


func _ambient_note() -> void:
	if Time.get_ticks_msec() - _last_urgent_ms < 8000:
		return
	var candidates: Array[Dictionary] = []
	if _needs != null:
		for id in NEED_IDS:
			var need: Need = _needs.need_by_id(id)
			if need != null and need.ratio() < 0.85:
				candidates.append({"text": _need_text(id, 1), "key": "ambient:%s" % id})
	if _body != null:
		var worst: BodyPart = null
		for part in _body.parts:
			if part.severity() >= BodyPart.Severity.LIGHT and (worst == null or part.severity() > worst.severity()):
				worst = part
		if worst != null:
			candidates.append({"text": _pain_text(worst), "key": "ambient:pain:%s" % worst.def.id})
	var sprint: Sprint = _player.get_component(Sprint) as Sprint
	if sprint != null and sprint.is_running():
		candidates.append({"text": "跑动让你听见自己的呼吸。", "key": "ambient:run", "chance": 0.25, "cooldown": 45.0})
	if _player_terrain() == Terrain.TALL_GRASS:
		candidates.append({"text": "高草在你身旁窸窣作响。", "key": "ambient:tall_grass", "chance": 0.25, "cooldown": 45.0})
	elif GrassField.has_grass(_player.coord):
		candidates.append({"text": "草叶在脚边沙沙作响。", "key": "ambient:grass", "chance": 0.25, "cooldown": 45.0})
	if candidates.is_empty():
		return
	for offset in candidates.size():
		var choice: Dictionary = candidates[(_ambient_turn + offset) % candidates.size()]
		if _rng.randf() < float(choice.get("chance", 1.0)) and _note(String(choice["text"]), QUIET,
				String(choice["key"]), float(choice.get("cooldown", 90.0))):
			_ambient_turn = (_ambient_turn + offset + 1) % candidates.size()
			return


func _note(message: String, priority: int, key: String, cooldown_seconds: float) -> bool:
	if message.is_empty():
		return false
	var now: int = Time.get_ticks_msec()
	if not key.is_empty() and now - int(_last_by_key.get(key, -1000000000)) < int(cooldown_seconds * 1000.0):
		return false
	var routine: bool = key.begins_with("routine:") or key.begins_with("ambient:")
	if routine and now - _last_routine_ms < ROUTINE_GAP_MS:
		return false
	if not key.is_empty():
		_last_by_key[key] = now
		if key.begins_with("need:"):
			_last_by_key["ambient:" + key.get_slice(":", 1)] = now
		elif key.begins_with("pain:"):
			_last_by_key["ambient:pain:" + key.get_slice(":", 1)] = now
	if priority == URGENT:
		_last_urgent_ms = now
	if routine:
		_last_routine_ms = now
	_entries.append({"day": TimeSystem.day(), "time": TimeSystem.time_string(), "text": message, "priority": priority})
	if _entries.size() > MAX_HISTORY:
		_entries.pop_front()
	_refresh_recent(true)
	_refresh_history()
	return true


func _refresh_recent(animate: bool) -> void:
	for line in _lines:
		line.text = ""
	var count: int = mini(3, _entries.size())
	if count == 0:
		_lines[2].text = "感受将出现在这里"
		_lines[2].modulate.a = 0.5
		return
	for i in count:
		var entry: Dictionary = _entries[_entries.size() - count + i]
		var line: Label = _lines[3 - count + i]
		line.text = "%s  %s" % [entry["time"], entry["text"]]
		line.tooltip_text = String(entry["text"])
		var color: Color = Color(0.76, 0.82, 0.80)
		if int(entry["priority"]) == NOTICE:
			color = Color(0.94, 0.78, 0.47)
		elif int(entry["priority"]) == URGENT:
			color = Color(1.0, 0.48, 0.38)
		line.add_theme_color_override("font_color", color)
		line.modulate.a = 1.0 if i == count - 1 else 0.64
	if animate:
		var latest: Label = _lines[2]
		latest.modulate.a = 0.0
		var tween: Tween = create_tween()
		tween.tween_property(latest, "modulate:a", 1.0, 0.25)


func _refresh_history() -> void:
	var contents: String = ""
	for entry in _entries:
		contents += "第%d天 %s  %s\n" % [entry["day"], entry["time"], entry["text"]]
	_history.text = contents
