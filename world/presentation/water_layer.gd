class_name WaterLayer
extends Node2D

## 湖岸线层 —— 把**任何** `ShoreSampler`（见 `world/shore_sampler.gd`）画成一条硬边岸线。
##
## 【职责边界】只说三件事：①水不填色 ②岸线是一条 N px 硬边线 ③多片水各烘各的。
##   它**不认识** `LakeGenerator`、不扫 `GridManager`、不问 `Terrain`：
##   想知道"水在哪、有多大"，一律问采样器自己的 `e()` / `bounds()`。
##   ⇒ 将来换一种水体（池塘 / 沼泽 / 河流）只要也实现 `ShoreSampler`，**本文件一行不改**。
##
## 【怎么画】**等值线提取**（marching squares 的角点判据）：
##   在每片水的包围盒内按**像素角点**采样 `e()`；某像素的 4 个角**不全同号**
##   => 岸线穿过该像素 => 涂色。
##   ⇒ 得到的线**必然 8 连通、恒为 1px**、硬像素无抗锯齿。
##
##   ⚠ 别改成"距离阈值取带"（旧版就是这么错的）：岸线接近垂直处会漏掉像素中心，
##     线**断成虚线**（实测只画到 1593 个像素、8 连通块 > 1）。角点判据才是对的。
##
## 【性能】逐格先筛（9 点采样判断该格是否含岸线），全水/全陆的格直接跳过 ——
##   否则整片包围盒逐像素求值（~90 万次噪声）跑不动；筛完只剩岸线那一圈格（~80 次/片）。
##   只在收到 `shorelines_changed` 时烘一次，**不是每帧**。

var _textures: Array[ImageTexture] = []
var _rects: Array[Rect2] = []
var _edge_width := 1
var _edge_color := Color.WHITE

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST    # 硬像素，不糊
	EventBus.shorelines_changed.connect(_on_shorelines_changed)

## 收到"岸线描述"就重烘。参数里**只有数据**，没有生成器 —— 这就是解耦的落点。
func _on_shorelines_changed(samplers: Array, edge_width_px: int, edge_color: Color) -> void:
	_edge_width = maxi(edge_width_px, 1)
	_edge_color = edge_color
	_rebuild(samplers)

func _rebuild(samplers: Array) -> void:
	_textures.clear()
	_rects.clear()
	var cs := int(Grid.CELL_SIZE)

	for item in samplers:
		var s := item as ShoreSampler
		if s == null:
			continue
		var b := s.bounds()
		if b.size.x <= 0.0 or b.size.y <= 0.0:
			continue

		var minx := int(floor(b.position.x))
		var miny := int(floor(b.position.y))
		var cw := maxi(int(ceil(b.position.x + b.size.x)) - minx, 1)
		var ch := maxi(int(ceil(b.position.y + b.size.y)) - miny, 1)
		var w := cw * cs
		var h := ch * cs

		var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var painted: Array[Vector2i] = []
		var band_cells := 0

		for cy in ch:
			for cx in cw:
				if not _cell_has_edge(s, minx + cx, miny + cy):
					continue
				band_cells += 1
				painted.append_array(_paint_cell(img, s, minx + cx, miny + cy, cx * cs, cy * cs))

		if painted.is_empty():
			continue
		if _edge_width > 1:
			_dilate(img, painted, w, h, _edge_width - 1)

		_textures.append(ImageTexture.create_from_image(img))
		_rects.append(Rect2(Vector2(minx, miny) * float(cs), Vector2(w, h)))
		print("[水域表现] 岸线 %d/%d 片：包围盒 %dx%d px（%d×%d 格）· 含岸线格 %d · 1px 线像素 %d · 线宽 %d px" % [
			_textures.size(), samplers.size(), w, h, cw, ch, band_cells, painted.size(), _edge_width])

	queue_redraw()

## 这一格是否被岸线穿过：cell 的 4 角 + 4 边中点 + 中心，9 个采样点不全同号即"有"。
func _cell_has_edge(s: ShoreSampler, gx: int, gy: int) -> bool:
	var fx := float(gx)
	var fy := float(gy)
	var pos := 0
	var neg := 0
	for j in 3:
		for i in 3:
			if s.e(fx + float(i) * 0.5, fy + float(j) * 0.5) < 0.0:
				neg += 1
			else:
				pos += 1
	return pos > 0 and neg > 0

## 在一格内逐像素求值并画线；返回本格画到的像素（图像坐标）。
func _paint_cell(img: Image, s: ShoreSampler, gx: int, gy: int, bx: int, by: int) -> Array[Vector2i]:
	var cs := int(Grid.CELL_SIZE)
	var n := cs + 1
	var inside := PackedByteArray()
	inside.resize(n * n)
	for j in n:
		var wy := float(gy) + float(j) / float(cs)
		var row := j * n
		for i in n:
			inside[row + i] = 1 if s.e(float(gx) + float(i) / float(cs), wy) < 0.0 else 0

	var out: Array[Vector2i] = []
	for j in cs:
		var r0 := j * n
		var r1 := r0 + n
		for i in cs:
			var a := inside[r0 + i]
			var b := inside[r0 + i + 1]
			var c := inside[r1 + i]
			var d := inside[r1 + i + 1]
			if a == b and b == c and c == d:
				continue                       # 四角同号 -> 岸线不在这像素里
			var px := bx + i
			var py := by + j
			img.set_pixel(px, py, _edge_color)
			out.append(Vector2i(px, py))
	return out

## 只对"已画像素"的 8 邻域做膨胀（而不是全图扫描）—— 线宽 > 1 时才走这条。
func _dilate(img: Image, painted: Array[Vector2i], w: int, h: int, rounds: int) -> void:
	var frontier := painted
	for _r in rounds:
		var add: Array[Vector2i] = []
		for p: Vector2i in frontier:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := p.x + dx
					var ny := p.y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if img.get_pixel(nx, ny).a > 0.5:
						continue
					img.set_pixel(nx, ny, _edge_color)
					add.append(Vector2i(nx, ny))
		frontier = add

func _draw() -> void:
	for i in _textures.size():
		draw_texture_rect(_textures[i], _rects[i], false)
