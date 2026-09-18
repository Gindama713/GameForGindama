class_name Minimap
extends Control

## 右上角小地图（DF 式）：整个逻辑网格的缩略图。
##   黑 = 陆地   生物 = def.map_color 色块（和主画面同一个数据、同一套约定）
## 【纪律】只读 GridManager，不持有任何生物引用；什么时候重画听信号，不每帧扫。

const PX_PER_CELL := 4       # 每格在缩略图上占几个像素（40x24 格 -> 160x96 px）
const MARGIN := 4            # 内容到外框的距离
const BORDER := Color.WHITE             # 外框：白（和画面里的"白=生物"同一个色系）

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	# 重画时机 = 生物 生成/移动/死亡/被移除 的瞬间，**完全事件驱动**。
	# 不再订阅 tick：不每帧重绘，暂停也自然冻结（事件本来就不会来）。
	EventBus.creature_spawned.connect(func(_c: Node) -> void: queue_redraw())
	EventBus.creature_moved.connect(func(_c: Node) -> void: queue_redraw())
	EventBus.creature_died.connect(func(_c: Node) -> void: queue_redraw())
	EventBus.creature_removed.connect(func(_c: Node) -> void: queue_redraw())

func _get_minimum_size() -> Vector2:
	# 首次布局可能早于 GridManager 就绪（实测会先查一次），没网格就先按 0 报
	if GridManager == null or GridManager.grid == null:
		return Vector2.ZERO
	var g := GridManager.grid
	return Vector2(g.width, g.height) * PX_PER_CELL + Vector2.ONE * (MARGIN * 2)

func _draw() -> void:
	if GridManager == null or GridManager.grid == null:
		return
	var g := GridManager.grid
	var s := PX_PER_CELL
	# 每格 4px：黑=陆地；活体=map_color；尸体=暗灰（永久留在格上，不占格）
	for y in g.height:
		for x in g.width:
			var cell := g.get_cell(Vector2i(x, y))
			var col := Color.BLACK
			if cell.content is Creature:
				col = cell.content.def.map_color
			elif cell.corpse != null:
				col = Creature.DEAD_COLOR
			draw_rect(Rect2(Vector2(x, y) * s + Vector2.ONE * MARGIN, Vector2(s, s)), col)
	# 外框
	var full := Vector2(g.width, g.height) * s + Vector2.ONE * (MARGIN * 2)
	draw_rect(Rect2(Vector2.ZERO, full), BORDER, false, 1.0)
