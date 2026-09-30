class_name WorldObjectField
extends Node2D

signal object_added(object: WorldObject)
signal object_changed(object: WorldObject)
signal object_removed(object: WorldObject)

@export var definitions: Array[WorldObjectDef] = []
@export var region_noise: FastNoiseLite
const GROWTH_REFRESH_MINUTES: float = 5.0

var _objects: Dictionary = {}  # 格坐标 -> WorldObject；Cell.feature 引用同一实例
var _next_id: int = 1
var _growing: Array[WorldObject] = []
var _growth_elapsed: float = 0.0


func _ready() -> void:
	TimeSystem.tick.connect(_on_tick)


func generate(seed_value: int) -> void:
	clear()
	_next_id = 1
	for placement in WorldObjectGenerator.generate(GridManager.grid, seed_value, definitions, region_noise):
		add(placement.definition, placement.coord, placement.initial_growth)
	var counts: Dictionary = {}
	for object: WorldObject in _objects.values():
		counts[object.definition.id] = int(counts.get(object.definition.id, 0)) + 1
	print("[地物生成] 种子=%d 数量=%s" % [seed_value, counts])


func add(definition: WorldObjectDef, coord: Vector2i, initial_growth: float = 100.0) -> WorldObject:
	if definition == null or not definition.validate().is_empty():
		push_error("无法建立无效地物")
		return null
	if not can_place(definition, coord):
		return null
	var object: WorldObject = WorldObject.new(_next_id, definition, coord, initial_growth, TimeSystem.elapsed)
	if not GridManager.place_feature(coord, object):
		return null
	_next_id += 1
	_objects[coord] = object
	if object.has_growth() and object.growth < 100.0:
		_growing.append(object)
	_adjust_terrain_exclusion(object, 1)
	object_added.emit(object)
	return object


## 种子物品将来调用这一入口；现在也可由世界逻辑直接种下一棵 0% 的树。
func plant(definition: WorldObjectDef, coord: Vector2i) -> WorldObject:
	if definition == null or definition.growth_duration_minutes <= 0.0:
		return null
	var cell: Grid.Cell = GridManager.grid.get_cell(coord)
	if cell == null or float(definition.terrain_weights.get(cell.terrain, 0.0)) <= 0.0:
		return null
	if not WorldObjectGenerator.fits_habitat(GridManager.grid, coord, definition):
		return null
	if definition.blocks_movement and not WorldObjectGenerator.keeps_routes(GridManager.grid, coord, {}):
		return null
	return add(definition, coord, 0.0)


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
		if object.visual_bounds_at().has_point(point):
			return object
	return null


func _on_tick(dt: float) -> void:
	if _growing.is_empty():
		return
	_growth_elapsed += dt
	if _growth_elapsed < GROWTH_REFRESH_MINUTES:
		return
	_growth_elapsed = fmod(_growth_elapsed, GROWTH_REFRESH_MINUTES)
	for i in range(_growing.size() - 1, -1, -1):
		var object: WorldObject = _growing[i]
		if object.advance_growth(TimeSystem.elapsed):
			object_changed.emit(object)
		if object.growth >= 100.0:
			_growing.remove_at(i)


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
	_growing.erase(object)
	_adjust_terrain_exclusion(object, -1)
	_objects.erase(coord)
	object_removed.emit(object)
	return true


func clear() -> void:
	for object in all_objects():
		remove(object.coord)
	_growth_elapsed = 0.0


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
