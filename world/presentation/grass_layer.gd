class_name GrassLayer
extends Node2D

## 草层 —— 只画**有活草的格**，叠在地形层（`MapRenderer`）之上。
##
## ── 【为什么要独立成层】──
##   草的变化是**高频**事件（实测 `grass_changed` **0.36 次/真实秒**，一游戏日 512 次）。
##   之前地形与草混在同一个 `_draw()` 里，每次重绘都要扫**全图 16900 格** ——
##   于是每约 2.8 秒一次 **~31 ms** 的尖峰（实测最差帧 45.1 ms vs 藏掉后 13.7 ms）。
##   而地形是静态的、草只占几百格 ⇒ 拆层之后，草变化只重画**这一层**，
##   而且本层**只遍历 `GrassField.tiles`**（开局 343 格，随扩散增长），不扫全图。
##   ⇒ 重绘成本从 O(16900) 降到 O(草格数)，**约 50 倍**。
##
## ── 【为什么必须先铺一层黑底】★ 这一步不能省 ★ ──
##   `world/art/grass.png` / `high-grass.png` 是**带透明通道**的线稿
##   （实测：grass.png 有 **71.7%** 的像素 alpha < 255，最低为 0）。
##   而改动前，草格是"**只画草贴图、不画地形**"（`continue` 掉了地形那一支）——
##   所以透明处露出来的是**清屏黑**（`default_clear_color`）。
##   拆层后如果只是把草贴图盖在地形层上，透明处就会透出**地形贴图** ——
##   **画面会变**，而且这种"透明度露出的底色变了"很难用肉眼发现。
##   ⇒ 每格先 `draw_rect(rect, BLACK)` 再画草，逐像素还原改动前的合成结果。
##     （验证方式见 `docs/代码审计_低耦合与硬编码.md`：改动前后各截一张首帧图做像素比对。）
##
## 【只读】读 `GrassField`（活草状态）与 `GridManager`（该格地形，决定用哪张贴图），不写任何逻辑。

## 秃(耐久 0)时的色调（枯黄），成熟(满)时用纯白（= 贴图原色）。按耐久比例线性插值。
const BARE_TINT := Color(0.62, 0.55, 0.30)

## 无贴图基底（`unknown` 黑土）上扩散出来的新草，回退用这张。
const GRASS_TEX: Texture2D = preload("res://world/art/grass.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 逐格铺贴图，保持硬像素不糊
	EventBus.grass_changed.connect(func(_c: Vector2i) -> void: queue_redraw())
	# 地形变了也要重画：本层按"该格地形"选贴图（高草→high-grass.png、黑土→grass.png），
	# 地形一变这个选择就变了。（本层不订阅 `grass_matured` / `grass_depleted` ——
	# 那两者都伴随 `grass_changed`，重复订阅只会多一次无用的 queue_redraw。）
	EventBus.terrain_changed.connect(queue_redraw)

func _draw() -> void:
	var s := Grid.CELL_SIZE
	# ⚠ **直接迭代 `GrassField.tiles` 的键**，不调 `.keys()`（那会每次分配一个新数组），
	#   也**不遍历全网格**（16900 格）—— 本层只关心"哪些格有草"。
	for coord in GrassField.tiles:
		var c: Vector2i = coord
		var cell := GridManager.cell_at(c.x, c.y)
		if cell == null:
			continue
		# ⚠ 显式标类型：`GrassField.tiles` 取出的是 Variant（事实文档 §2.4 坑 7）。
		var tile := GrassField.tiles[coord] as GrassTile
		if tile == null:
			continue
		var rect := Rect2(Vector2(c) * s, Vector2(s, s))
		# 黑底：还原"草格不画地形"的旧合成结果（见文件头 ★ 段）
		draw_rect(rect, Color.BLACK)
		var tex := Terrain.texture_of(cell.terrain)
		if tex == null:
			tex = GRASS_TEX                       # 黑土上扩散出的草没有对应贴图
		draw_texture_rect(tex, rect, false, BARE_TINT.lerp(Color.WHITE, tile.ratio()))
