class_name WorldObject
extends RefCounted

## 地物个体状态。格子、查询和画面引用同一个对象，生命周期由 Field 管理。
var id: int
var definition: WorldObjectDef
var coord: Vector2i
var integrity: int


func _init(p_id: int, p_definition: WorldObjectDef, p_coord: Vector2i) -> void:
	id = p_id
	definition = p_definition
	coord = p_coord
	integrity = definition.max_integrity


## 通用网格只认通行协议，不依赖树、石头等具体类型。
func blocks_movement() -> bool:
	return definition.blocks_movement
