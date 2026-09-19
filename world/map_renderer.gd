class_name MapRenderer
extends Node2D

## 地图渲染层 —— 把逻辑网格画成 DF 式地图。
## 【纪律】只读不写：terrain 怎么变是逻辑层的事，这里只画。
##
## 表现**不写在本文件**：统一问 Terrain 注册表（一事实来源），规则与生物一致：
##   **有贴图就用贴图**（`grass` / `tall_grass` = `world/art/*.png`），没贴图的才用 `color` 色块兜底。
##   加一种地形 = 改 Terrain，本文件一行不改。
##
## 130×130 = 16900 格。**静态画布**：地形变化或草场变化（啃食/再生/扩散）时重画。
## 有活草的格按 GrassField.durability 调制颜色（秃→枯黄、成熟→浓绿）；无活草才回落到地形底图。

## 秃(耐久0)时的色调（枯黄），成熟(满)时用纯白（=贴图原色，浓绿）。按耐久比例线性插值。
const BARE_TINT := Color(0.62, 0.55, 0.30)
const GRASS_TEX: Texture2D = preload("res://world/art/grass.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 逐格铺贴图，保持硬像素不糊
	EventBus.terrain_changed.connect(queue_redraw)
	EventBus.grass_changed.connect(func(_c: Vector2i) -> void: queue_redraw())

func _draw() -> void:
	var g := GridManager.grid
	if g == null:
		return
	var s := Grid.CELL_SIZE
	for y in g.height:
		for x in g.width:
			var cell := g.get_cell(Vector2i(x, y))
			if cell == null:
				continue
			var coord := Vector2i(x, y)
			var rect := Rect2(Vector2(x, y) * s, Vector2(s, s))
			var ratio := GrassField.ratio_of(coord)       # <0 = 该格无活草
			if ratio >= 0.0:
				# 有活草：贴图仍按该格地形选（高草→high-grass.png、普通草→grass.png），
				# 只有扩散到无贴图基底(unknown 黑土)上的新草才回退用 grass.png；再按耐久着色。
				var gtex := Terrain.texture_of(cell.terrain)
				if gtex == null:
					gtex = GRASS_TEX
				draw_texture_rect(gtex, rect, false, BARE_TINT.lerp(Color.WHITE, ratio))
				continue
			var tex := Terrain.texture_of(cell.terrain)
			if tex != null:
				draw_texture_rect(tex, rect, false)                 # 有图用图
			else:
				draw_rect(rect, Terrain.color_of(cell.terrain))     # 无图兜底
