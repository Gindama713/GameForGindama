class_name WorldObjectDef
extends Resource

## 地物性质与生成条件。外观使用原图，不做随机染色、偏移或旋转。固定朝向由资源定义。
@export var id: StringName
@export var display_name: String
@export var texture: Texture2D
@export var height_cells: float = 1.0
@export var rotation_degrees: float = 0.0
## 整个外观及留白都避开这些地形。
@export var excluded_terrains: Array[StringName] = []
## 原图中落在逻辑格中心的点。树用树干根部，其余物体用中心。
@export var anchor: Vector2 = Vector2(0.5, 0.5)
## 共享区域噪声从 0 到 1，曲线决定该区域的生成密度。
@export var region_density: Curve
@export var gather_item: ItemDef
@export var gather_amount: int = 1
@export var gather_action: String = ""
@export var blocks_movement: bool = false
@export var max_integrity: int = 1
@export var terrain_weights: Dictionary = {}
## 非空时，落点附近必须存在其中一种地形；例如草地边缘的野花。
@export var nearby_terrains: Array[StringName] = []
@export var nearby_radius_cells: int = 1
@export_range(0.0, 1.0) var density: float = 0.3
@export var patch_noise: FastNoiseLite
@export_range(-1.0, 0.99) var patch_threshold: float = 0.0
@export var spacing_cells: float = 1.0
## 与不可走地形、地图边界的留白，单位为格。
@export var land_margin_cells: int = 0


func visual_rect_cells() -> Rect2:
	var dimensions: Vector2 = Vector2(float(texture.get_width()) / texture.get_height(), 1.0) * height_cells
	var origin: Vector2 = -dimensions * anchor
	var angle: float = deg_to_rad(rotation_degrees)
	var bounds: Rect2 = Rect2(origin.rotated(angle), Vector2.ZERO)
	for corner: Vector2 in [origin + Vector2(dimensions.x, 0), origin + Vector2(0, dimensions.y), origin + dimensions]:
		bounds = bounds.expand(corner.rotated(angle))
	return bounds


func bounds_at(coord: Vector2i) -> Rect2:
	var bounds: Rect2 = visual_rect_cells()
	bounds.position += Vector2(coord) + Vector2(0.5, 0.5)
	return bounds


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or display_name.strip_edges().is_empty() or texture == null:
		errors.append("地物需要 id、display_name 和 texture")
	if patch_noise == null or patch_noise.frequency <= 0.0:
		errors.append("地物需要频率大于零的 patch_noise")
	if density < 0.0 or density > 1.0 or patch_threshold < -1.0 or patch_threshold >= 1.0:
		errors.append("density 或 patch_threshold 超出范围")
	if height_cells <= 0.0 or max_integrity < 1 or spacing_cells < 0.0 or land_margin_cells < 0:
		errors.append("尺寸、耐久或间距无效")
	if anchor.x < 0.0 or anchor.x > 1.0 or anchor.y < 0.0 or anchor.y > 1.0:
		errors.append("anchor 必须在原图范围内")
	if region_density == null or region_density.point_count < 2:
		errors.append("需要至少两个控制点的 region_density")
	if gather_item != null:
		errors.append_array(gather_item.validate())
		if gather_amount <= 0 or gather_action.strip_edges().is_empty():
			errors.append("采集需要数量和动作名称")
	elif not gather_action.is_empty():
		errors.append("采集动作缺少产物")
	if terrain_weights.is_empty():
		errors.append("terrain_weights 不能为空")
	if nearby_radius_cells < 0:
		errors.append("nearby_radius_cells 不能为负")
	for terrain in excluded_terrains:
		if not Terrain.DEFS.has(terrain):
			errors.append("无效的排除地形：%s" % terrain)
	for terrain in nearby_terrains:
		if not Terrain.DEFS.has(terrain):
			errors.append("无效的邻近地形：%s" % terrain)
	for terrain: Variant in terrain_weights:
		if not Terrain.DEFS.has(StringName(terrain)) or float(terrain_weights[terrain]) < 0.0 or float(terrain_weights[terrain]) > 1.0:
			errors.append("无效的地形权重：%s" % terrain)
	return errors
