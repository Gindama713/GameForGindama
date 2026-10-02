class_name WorldObject
extends RefCounted

## 地物个体状态。格子、查询和画面引用同一个对象，生命周期由 Field 管理。
var id: int
var definition: WorldObjectDef
var coord: Vector2i
var integrity: int
var growth: float = 100.0
var dropped_by_creature: bool = false
var _growth_updated_at: float = 0.0


func _init(p_id: int, p_definition: WorldObjectDef, p_coord: Vector2i,
		initial_growth: float = 100.0, now: float = 0.0) -> void:
	id = p_id
	definition = p_definition
	coord = p_coord
	integrity = definition.max_integrity
	growth = clampf(initial_growth, 0.0, 100.0) if has_growth() else 100.0
	_growth_updated_at = now


func has_growth() -> bool:
	return definition.growth_duration_minutes > 0.0


func growth_percent() -> int:
	return floori(growth)


## 只有跨过一个可显示的百分点时通知视图，成长速度与帧率无关。
func advance_growth(now: float) -> bool:
	if not has_growth() or growth >= 100.0:
		return false
	var before: int = growth_percent()
	growth = minf(100.0, growth + maxf(0.0, now - _growth_updated_at) * 100.0 / definition.growth_duration_minutes)
	_growth_updated_at = now
	return growth_percent() != before


func visual_texture() -> Texture2D:
	return definition.seed_texture if has_growth() and growth < definition.sprout_at_percent else definition.texture


func visual_height_cells() -> float:
	if not has_growth():
		return definition.height_cells
	if growth < definition.sprout_at_percent:
		return definition.seed_height_cells
	var progress: float = (growth - definition.sprout_at_percent) / (100.0 - definition.sprout_at_percent)
	return lerpf(definition.sapling_height_cells, definition.height_cells, progress)


func visual_anchor() -> Vector2:
	return definition.seed_anchor if has_growth() and growth < definition.sprout_at_percent else definition.anchor


func visual_bounds_at() -> Rect2:
	var bounds: Rect2 = definition.visual_rect_cells_for(visual_texture(), visual_height_cells(), visual_anchor())
	bounds.position += Vector2(coord) + Vector2(0.5, 0.5)
	return bounds


## 通用网格只认通行协议，不依赖树、石头等具体类型。
func blocks_movement() -> bool:
	return definition.blocks_movement
