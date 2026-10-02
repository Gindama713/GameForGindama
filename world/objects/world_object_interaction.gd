class_name WorldObjectInteraction
extends Node

signal inspect_requested(coord: Vector2i)
signal action_failed(reason: String)

@onready var _field: WorldObjectField = get_parent() as WorldObjectField
var _player: Creature


func _ready() -> void:
	EventBus.player_spawned.connect(_bind)


func _bind(node: Node) -> void:
	_player = node as Creature


func _actor_reason() -> String:
	if _player == null or not is_instance_valid(_player) or not _player.is_alive():
		return "无法行动"
	if TimeSystem.paused:
		return "游戏已暂停"
	var sleep: Sleep = _player.get_component(Sleep) as Sleep
	if sleep != null and not sleep.can_act():
		return "先醒来"
	var body: Body = _player.get_component(Body) as Body
	if body != null and not body.can_grasp():
		return "手臂无法抓握"
	if _player.get_component(Inventory) == null:
		return "无法携带物品"
	return ""


func gather_reason(coord: Vector2i) -> String:
	var reason: String = _actor_reason()
	if not reason.is_empty():
		return reason
	if absi(coord.x - _player.coord.x) + absi(coord.y - _player.coord.y) > 1:
		return "走到旁边或同一格"
	var object: WorldObject = _field.object_at(coord)
	if object == null or object.definition.gather_item == null:
		return "没有可收集的物品"
	var inventory: Inventory = _player.get_component(Inventory) as Inventory
	if not inventory.can_add(object.definition.gather_item, object.definition.gather_amount):
		return "没有空闲的手，每只手只能拿一件。"
	return ""


func gather(coord: Vector2i) -> bool:
	var reason: String = gather_reason(coord)
	if not reason.is_empty():
		action_failed.emit(reason)
		return false
	var object: WorldObject = _field.object_at(coord)
	var inventory: Inventory = _player.get_component(Inventory) as Inventory
	# 先从世界移除，再通知物品与 UI；信号回调不能重复收集同一对象。
	if not _field.remove(coord):
		return false
	if not inventory.add(object.definition.gather_item, object.definition.gather_amount):
		var restored: WorldObject = _field.add(object.definition, coord)
		if restored != null:
			restored.integrity = object.integrity
			restored.dropped_by_creature = object.dropped_by_creature
		return false
	if not object.dropped_by_creature and object.definition.gather_skill != &"":
		var skills: Skills = _player.get_component(Skills) as Skills
		if skills != null:
			skills.practice(object.definition.gather_skill)
	return true


func drop_hand(hand_index: int) -> void:
	var reason: String = _actor_reason()
	if not reason.is_empty():
		action_failed.emit(reason)
		return
	var inventory: Inventory = _player.get_component(Inventory) as Inventory
	var slots: Array[Dictionary] = inventory.hand_slots()
	if hand_index < 0 or hand_index >= slots.size():
		return
	var item: ItemDef = slots[hand_index]["item"] as ItemDef
	if item == null:
		return
	var definition: WorldObjectDef = null
	for candidate in _field.definitions:
		if candidate.gather_item == item:
			definition = candidate
			break
	if definition == null:
		action_failed.emit("这个物品还不能放到地上。")
		return
	var nearby: Array[Vector2i] = [Vector2i.ZERO]
	nearby.append_array(GridMover.DIRS)
	for direction in nearby:
		var coord: Vector2i = _player.coord + direction
		if _field.can_place(definition, coord):
			var dropped: WorldObject = _field.add(definition, coord)
			if dropped != null:
				dropped.dropped_by_creature = true
				inventory.take_from_hand(hand_index)
				return
	action_failed.emit("身旁没有能放下物品的空地。")


func _unhandled_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = get_viewport().canvas_transform.affine_inverse() * mouse.position
		var object: WorldObject = _field.object_at_world_position(point)
		if object != null and object.definition.gather_item != null:
			if not gather(object.coord):
				inspect_requested.emit(object.coord)
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("interact") or event.is_echo() or _player == null or not is_instance_valid(_player):
		return
	var nearby: Array[Vector2i] = [Vector2i.ZERO]
	nearby.append_array(GridMover.DIRS)
	for direction in nearby:
		var object: WorldObject = _field.object_at(_player.coord + direction)
		if object != null and object.definition.gather_item != null:
			gather(object.coord)
			get_viewport().set_input_as_handled()
			return
