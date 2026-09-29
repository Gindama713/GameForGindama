class_name WorldObjectField
extends Node2D

signal object_added(object: WorldObject)
signal object_changed(object: WorldObject)
signal object_removed(object: WorldObject)

@export var definitions: Array[WorldObjectDef] = []
@export var region_noise: FastNoiseLite
var _objects: Dictionary = {}  # 格坐标 -> WorldObject；Cell.feature 引用同一实例
var _next_id: int = 1


func generate(seed_value: int) -> void:
	clear()
	_next_id = 1
	for placement in WorldObjectGenerator.generate(GridManager.grid, seed_value, definitions, region_noise):
		add(placement.definition, placement.coord)
	var counts: Dictionary = {}
	for object: WorldObject in _objects.values():
		counts[object.definition.id] = int(counts.get(object.definition.id, 0)) + 1
	print("[地物生成] 种子=%d 数量=%s" % [seed_value, counts])


func add(definition: WorldObjectDef, coord: Vector2i) -> WorldObject:
	if definition == null or not definition.validate().is_empty():
		push_error("无法建立无效地物")
		return null
	if not can_place(definition, coord):
		return null
	var object: WorldObject = WorldObject.new(_next_id, definition, coord)
	if not GridManager.place_feature(coord, object):
		return null
	_next_id += 1
	_objects[coord] = object
	_adjust_terrain_exclusion(object, 1)
	object_added.emit(object)
	return object


func can_place(definition: WorldObjectDef, coord: Vector2i) -> bool:
	if _objects.has(coord) or not WorldObjectGenerator.fits_land(GridManager.grid, coord, definition):
		return false
	var bounds: Rect2 = definition.bounds_at(coord)
	# ponytail: 放置时扫描现有外观边界；对象数达到数万时再加空间索引。
	for object in all_objects():
		if bounds.intersects(object.definition.bounds_at(object.coord)):
			return false
	return true


func object_at_world_position(world_position: Vector2) -> WorldObject:
	var point: Vector2 = world_position / Grid.CELL_SIZE
	for object in all_objects():
		if object.definition.bounds_at(object.coord).has_point(point):
			return object
	return null


func object_at(coord: Vector2i) -> WorldObject:
	return _objects.get(coord)


func all_objects() -> Array[WorldObject]:
	var result: Array[WorldObject] = []
	for object: WorldObject in _objects.values():
		result.append(object)
	return result


func damage(coord: Vector2i, amount: int) -> bool:
	var object: WorldObject = object_at(coord)
	if object == null or amount <= 0:
		return false
	object.integrity = maxi(0, object.integrity - amount)
	if object.integrity == 0:
		remove(coord)
	else:
		object_changed.emit(object)
	return true


func remove(coord: Vector2i) -> bool:
	var object: WorldObject = object_at(coord)
	if object == null:
		return false
	GridManager.remove_feature(coord, object)
	_adjust_terrain_exclusion(object, -1)
	_objects.erase(coord)
	object_removed.emit(object)
	return true


func clear() -> void:
	for object in all_objects():
		remove(object.coord)


func _adjust_terrain_exclusion(object: WorldObject, change: int) -> void:
	if object.definition.excluded_terrains.is_empty():
		return
	var bounds: Rect2 = object.definition.bounds_at(object.coord)
	var margin: Vector2i = Vector2i.ONE * object.definition.land_margin_cells
	var first: Vector2i = Vector2i(bounds.position.floor()) - margin
	var last: Vector2i = Vector2i(bounds.end.ceil()) - Vector2i.ONE + margin
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for terrain in object.definition.excluded_terrains:
				GridManager.adjust_terrain_exclusion(Vector2i(x, y), terrain, change)


func _exit_tree() -> void:
	clear()
