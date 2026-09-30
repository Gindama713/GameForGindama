class_name WorldObjectGenerator
extends RefCounted

## 地形与噪声决定片区；只产出逻辑格坐标，落入世界由 Field 完成。
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

class Placement:
	var definition: WorldObjectDef
	var coord: Vector2i
	var initial_growth: float = 100.0


static func generate(grid: Grid, seed_value: int, definitions: Array[WorldObjectDef], region_noise: FastNoiseLite) -> Array[Placement]:
	var result: Array[Placement] = []
	if region_noise == null or region_noise.frequency <= 0.0:
		push_error("地物生成缺少区域噪声")
		return result
	var regions: FastNoiseLite = region_noise.duplicate() as FastNoiseLite
	regions.seed = seed_value
	var occupied: Dictionary = {}
	var ids: Dictionary = {}
	var max_spacing: float = 0.0
	for definition in definitions:
		if definition == null or not definition.validate().is_empty():
			push_error("地物生成配置无效")
			return result
		if ids.has(definition.id):
			push_error("地物 id 重复：%s" % definition.id)
			return result
		ids[definition.id] = true
		max_spacing = maxf(max_spacing, maxf(definition.spacing_cells, definition.visual_rect_cells().size.length()))
	for definition in definitions:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value ^ String(definition.id).hash()
		var growth_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		growth_rng.seed = rng.seed ^ 0x47524F57
		var noise: FastNoiseLite = definition.patch_noise.duplicate() as FastNoiseLite
		noise.seed = rng.randi()
		var candidates: Array[Vector2i] = []
		for y in grid.height:
			for x in grid.width:
				var coord: Vector2i = Vector2i(x, y)
				var cell: Grid.Cell = grid.get_cell(coord)
				if float(definition.terrain_weights.get(cell.terrain, 0.0)) > 0.0 and cell.feature == null:
					candidates.append(coord)
		# 使用专用 RNG 洗牌，不消费生物随机流，也不按扫描顺序排出横行。
		for i in range(candidates.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swapped: Vector2i = candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = swapped
		for coord in candidates:
			if occupied.has(coord) or not fits_land(grid, coord, definition):
				continue
			var cell: Grid.Cell = grid.get_cell(coord)
			if definition.blocks_movement and cell.content != null:
				continue
			if noise.get_noise_2d(coord.x, coord.y) < definition.patch_threshold:
				continue
			var region: float = clampf((regions.get_noise_2d(coord.x, coord.y) + 1.0) * 0.5, 0.0, 1.0)
			var regional_density: float = clampf(definition.region_density.sample(region), 0.0, 1.0)
			if rng.randf() >= definition.density * regional_density * float(definition.terrain_weights[cell.terrain]):
				continue
			if not fits_habitat(grid, coord, definition):
				continue
			if _crowded(coord, definition, occupied, max_spacing):
				continue
			if definition.blocks_movement and not keeps_routes(grid, coord, occupied):
				continue
			var placement: Placement = Placement.new()
			placement.definition = definition
			placement.coord = coord
			if definition.growth_duration_minutes > 0.0:
				placement.initial_growth = clampf(definition.wild_growth_distribution.sample(growth_rng.randf()) * 100.0, 0.0, 100.0)
			occupied[coord] = placement
			result.append(placement)
	return result


static func fits_habitat(grid: Grid, coord: Vector2i, definition: WorldObjectDef) -> bool:
	if definition.nearby_terrains.is_empty():
		return true
	var radius: int = definition.nearby_radius_cells
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + y * y > radius * radius:
				continue
			var cell: Grid.Cell = grid.get_cell(coord + Vector2i(x, y))
			if cell != null and definition.nearby_terrains.has(cell.terrain):
				return true
	return false


static func fits_land(grid: Grid, coord: Vector2i, definition: WorldObjectDef) -> bool:
	var bounds: Rect2 = definition.visual_rect_cells()
	var center: Vector2 = Vector2(coord) + Vector2(0.5, 0.5)
	var margin: Vector2i = Vector2i.ONE * definition.land_margin_cells
	var first: Vector2i = Vector2i((center + bounds.position).floor()) - margin
	var last: Vector2i = Vector2i((center + bounds.end).ceil()) - Vector2i.ONE + margin
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell: Grid.Cell = grid.get_cell(Vector2i(x, y))
			if cell == null or not Terrain.walkable(cell.terrain) or definition.excluded_terrains.has(cell.terrain):
				return false
	return true


static func _crowded(coord: Vector2i, definition: WorldObjectDef, occupied: Dictionary, max_spacing: float) -> bool:
	var radius: int = ceili(max_spacing * 2.0)
	var bounds: Rect2 = definition.bounds_at(coord)
	for y in range(coord.y - radius, coord.y + radius + 1):
		for x in range(coord.x - radius, coord.x + radius + 1):
			var other: Placement = occupied.get(Vector2i(x, y))
			if other != null:
				var gap: float = maxf(definition.spacing_cells, other.definition.spacing_cells)
				if (coord - other.coord).length_squared() < gap * gap or bounds.intersects(other.definition.bounds_at(other.coord)):
					return true
	return false


static func _open(grid: Grid, coord: Vector2i, occupied: Dictionary) -> bool:
	var cell: Grid.Cell = grid.get_cell(coord)
	if cell == null or not Terrain.walkable(cell.terrain):
		return false
	if cell.feature != null and bool(cell.feature.call("blocks_movement")):
		return false
	var placed: Placement = occupied.get(coord)
	return placed == null or not placed.definition.blocks_movement


## 放下阻挡物前，四邻出口必须仍能从周围一圈互通，避免逐步封死通路。
## ponytail: 只接受局部能证实连通的落点；大面积密林需要完整连通分析时再扩展。
static func keeps_routes(grid: Grid, coord: Vector2i, occupied: Dictionary) -> bool:
	var exits: Array[Vector2i] = []
	for direction in DIRECTIONS:
		if _open(grid, coord + direction, occupied):
			exits.append(coord + direction)
	if exits.is_empty():
		return false
	var queue: Array[Vector2i] = [exits[0]]
	var seen: Dictionary = {exits[0]: true}
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if next == coord or seen.has(next) or abs(next.x - coord.x) > 1 or abs(next.y - coord.y) > 1:
				continue
			if _open(grid, next, occupied):
				seen[next] = true
				queue.append(next)
	for exit_coord in exits:
		if not seen.has(exit_coord):
			return false
	return true
