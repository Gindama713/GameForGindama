class_name MapRenderer
extends Node2D

## 地图**地形层** —— 把逻辑网格画成 DF 式地图。
## 【纪律】只读不写：terrain 怎么变是逻辑层的事，这里只画。
##
## ── 【2026-09-21 拆层】为什么把"草"从这里拿出去 ──
##   原先本文件把「地形 + 活草」混在同一个 `_draw()` 里画，于是**每次重绘都要扫全图 16900 格**。
##   而"草变了"是**高频**事件（实测 **0.36 次/真实秒**）——
##   每约 2.8 秒就有一次 **~31 ms** 的尖峰（实测：最差帧 **45.1 ms**，
##   把本层藏起来后同一段只剩 **13.7 ms**）。平均帧率不受影响（5.6 ms / 178 FPS），
##   但那是**周期性掉帧**，肉眼看得出。
##
##   而**地形是静态的** —— 一局里只在 `terrain_changed` 时变（开局一次）。于是拆开：
##     · **本文件**：只画地形，只订阅 `terrain_changed`
##     · **`world/grass_layer.gd`**：只画有活草的格，订阅 `grass_changed`，
##       而且**只遍历草格表**（开局几百格）而不是全图
##   ⇒ 这才是 `EventBus.grass_changed` 注释里"供表现层**局部**重画"那句话的落地。
##     （在此之前，信号带了格坐标，唯一的接收方却丢掉坐标做全量重绘 —— 契约与实现不一致。）
##
## 【表现规则】统一问 Terrain 注册表（一事实来源）：
##   **有贴图就用贴图**（`grass` / `tall_grass` = `world/art/*.png`），没贴图的才用 `color` 色块兜底。
##   加一种地形 = 改 Terrain，本文件一行不改。
##
## ⚠ **本层会把"有草的格"也照常画一遍**，随后由草层盖上去。看着像白做，但反过来
##   （本层跳过有草的格）会让本层依赖 `GrassField`、并且必须在草变化时重绘 ——
##   那就把刚拆开的两层又焊回去了。而本层**极少重绘**，多画的那点是一次性成本。

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 逐格铺贴图，保持硬像素不糊
	# 只订阅地形变化。**不再订阅 grass_changed** —— 那是草层的事（见文件头）。
	EventBus.terrain_changed.connect(queue_redraw)

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
			var rect := Rect2(Vector2(x, y) * s, Vector2(s, s))
			var tex := Terrain.texture_of(cell.terrain)
			if tex != null:
				draw_texture_rect(tex, rect, false)                 # 有图用图
			else:
				draw_rect(rect, Terrain.color_of(cell.terrain))     # 无图兜底
