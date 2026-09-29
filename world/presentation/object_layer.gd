extends Node2D

## 只显示 Field 中的对象。状态、占格和耐久不由精灵持有。
var _views: Dictionary = {}  # 稳定 ID -> Sprite2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var field: WorldObjectField = get_parent() as WorldObjectField
	field.object_added.connect(_add)
	field.object_removed.connect(_remove)
	for object in field.all_objects():
		_add(object)


func _add(object: WorldObject) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Object_%d" % object.id
	sprite.texture = object.definition.texture
	sprite.rotation_degrees = object.definition.rotation_degrees
	sprite.offset = sprite.texture.get_size() * (Vector2(0.5, 0.5) - object.definition.anchor)
	var factor: float = Grid.CELL_SIZE * object.definition.height_cells / sprite.texture.get_height()
	sprite.scale = Vector2.ONE * factor
	sprite.position = GridManager.grid.grid_to_world(object.coord) + Vector2.ONE * Grid.CELL_SIZE * 0.5
	_views[object.id] = sprite
	add_child(sprite)


func _remove(object: WorldObject) -> void:
	var sprite: Sprite2D = _views.get(object.id)
	if sprite != null:
		_views.erase(object.id)
		remove_child(sprite)
		sprite.queue_free()
