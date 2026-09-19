class_name Minimap
extends Control

## 右上角小地图 —— **只显示当前视野（"视线内"）那一片**。
## 【用户拍板 2026-09-19】世界有 100×100，但小地图不再画整张世界（那样又大又没意义），
##   只画**相机此刻看得见**的格矩形，随相机平移 / 缩放跟着变。
##
## 【纪律】只读：读 GridManager（地形 / 生物）与当前相机的可视矩形，不持有任何引用。
## 【实现】地形仍烘一张"全图"ImageTexture（每格 1 像素）；_draw 用
##   draw_texture_rect_region 只取**可视子矩形**画出来 -> 相机动只换取样窗口，不重建底图。
##
## 【关于"隐蔽"】主画面里藏进高草的生物**完全看不见**（用户拍板 2026-09-19）；
##   小地图是开发者的俯视图，**仍显示**它们 —— 否则无法观察隐藏行为。刻意的不一致。
## 【相机没有信号】故用 _process 轮询"可视矩形"，变了才重画（O(1) 比较，不重建底图）。

const MAX_SIDE := 150.0        # 小地图长边最多占多少像素（自适应）
const MARGIN := 4
const BORDER := Color.WHITE
const DOT_MIN_PX := 2.0        # 生物色块最小边长（缩小时仍看得见）

var _terrain_tex: ImageTexture = null
var _last_rect := Rect2i(-1, -1, 0, 0)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 放大时保持硬像素，不糊
	# 地形：只在变化时重建底图；生物：生成 / 移动 / 死亡 / 移除时重画点。
	EventBus.terrain_changed.connect(_rebuild_terrain)
	EventBus.creature_spawned.connect(func(_c: Node) -> void: queue_redraw())
	EventBus.creature_moved.connect(func(_c: Node) -> void: queue_redraw())
	EventBus.creature_died.connect(func(_c: Node) -> void: queue_redraw())
	EventBus.creature_removed.connect(func(_c: Node) -> void: queue_redraw())
	_rebuild_terrain()

func _grid() -> Grid:
	if GridManager == null:
		return null
	return GridManager.grid

## 把**整张**地形烘成一张 w×h 的图（每格 1 像素）。只在地形变化时重建一次。
## 小地图只是从这张图上"开一个窗口"看，窗口位置由相机决定。
func _rebuild_terrain() -> void:
	var g := _grid()
	if g == null:
		return
	var img := Image.create_empty(g.width, g.height, false, Image.FORMAT_RGBA8)
	for y in g.height:
		for x in g.width:
			var cell := g.get_cell(Vector2i(x, y))
			var col: Color = Terrain.color_of(cell.terrain) if cell != null else Color.BLACK
			img.set_pixel(x, y, col)
	_terrain_tex = ImageTexture.create_from_image(img)
	queue_redraw()

## 相机此刻"看得见"的格矩形（世界像素 -> 格），夹到地图范围内。
## 相机还没就绪时退回全图。
func _visible_cells() -> Rect2i:
	var g := _grid()
	if g == null:
		return Rect2i()
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2i(0, 0, g.width, g.height)
	var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom
	var center := cam.get_screen_center_position()
	var s := float(Grid.CELL_SIZE)
	var x0 := clampi(int(floor((center.x - half.x) / s)), 0, g.width)
	var y0 := clampi(int(floor((center.y - half.y) / s)), 0, g.height)
	var x1 := clampi(int(ceil((center.x + half.x) / s)), 0, g.width)
	var y1 := clampi(int(ceil((center.y + half.y) / s)), 0, g.height)
	return Rect2i(x0, y0, maxi(x1 - x0, 1), maxi(y1 - y0, 1))

## 每格像素（按当前可视格数自适应，长边封顶 MAX_SIDE）。
func _scale_for(cells: Vector2i) -> float:
	return MAX_SIDE / float(maxi(maxi(cells.x, cells.y), 1))

func _get_minimum_size() -> Vector2:
	var r := _visible_cells()
	if r.size == Vector2i.ZERO:
		return Vector2.ZERO
	return Vector2(r.size) * _scale_for(r.size) + Vector2.ONE * (MARGIN * 2)

## 相机没有信号 -> 每帧比一下可视矩形，变了才重画（也才重算尺寸）。
func _process(_delta: float) -> void:
	var r := _visible_cells()
	if r == _last_rect:
		return
	var size_changed := r.size != _last_rect.size
	_last_rect = r
	if size_changed:
		update_minimum_size()
	queue_redraw()

func _draw() -> void:
	if _terrain_tex == null:
		return
	var r := _visible_cells()
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var s := _scale_for(r.size)
	var full := Vector2(r.size) * s
	# ① 地形：从"全图烘图"里取**可视子矩形**（src 以像素计 = 以格计）
	draw_texture_rect_region(_terrain_tex, Rect2(Vector2.ONE * MARGIN, full), Rect2(Vector2(r.position), Vector2(r.size)))
	# ② 生物俯视点（仅可视范围内）：活体 = map_color；尸体 = 暗灰（永久留格、不占格）
	var dot := maxf(s, DOT_MIN_PX)
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var cell := GridManager.cell_at(x, y)
			if cell == null:
				continue
			var col := Color(0.0, 0.0, 0.0, 0.0)
			if cell.content is Creature:
				col = (cell.content as Creature).def.map_color
			elif cell.corpse != null:
				col = Creature.DEAD_COLOR
			else:
				continue
			draw_rect(Rect2(Vector2(x - r.position.x, y - r.position.y) * s + Vector2.ONE * MARGIN, Vector2(dot, dot)), col)
	# ③ 外框
	draw_rect(Rect2(Vector2.ZERO, full + Vector2.ONE * (MARGIN * 2)), BORDER, false, 1.0)
