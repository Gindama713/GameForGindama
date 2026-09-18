class_name PixelBar
extends Control

## 像素风分段条 —— 不是 ProgressBar 控件，而是自己画的一排小方块。
## 灰白填充 + 暗灰空格，契合像素美术基调；用 set_ratio() 更新。

@export var segments: int = 10          # 段数
@export var cell: Vector2 = Vector2(8, 8)  # 每段方块大小
@export var gap: int = 2                # 段间距

const FILL := Color(0.82, 0.82, 0.82)   # 灰白（满）
const EMPTY := Color(0.22, 0.22, 0.22)  # 暗灰（空）

var value: float = 1.0                  # 0..1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不抢拖窗事件

func set_ratio(r: float) -> void:
	value = clampf(r, 0.0, 1.0)
	queue_redraw()

func _get_minimum_size() -> Vector2:
	return Vector2(segments * (cell.x + gap) - gap, cell.y)

func _draw() -> void:
	var filled := int(round(value * segments))
	for i in segments:
		var col := FILL if i < filled else EMPTY
		draw_rect(Rect2(Vector2(i * (cell.x + gap), 0), cell), col)
