extends ColorRect

## 夜晚变暗：全屏叠一层黑，随时间平滑过渡（黄昏渐暗 → 深夜最深 → 黎明渐亮）。
## 【位置】UI CanvasLayer 的**第一个子节点** —— 盖在生物/地表之上、其它 UI 之下，
##   所以猪会随夜色变暗，而时钟/检视面板/小地图仍保持明亮可读。
## 【纪律】只读 TimeSystem，不改任何游戏状态。
##
## 注意（实测坑）：`set_anchors_preset(PRESET_FULL_RECT)` 会**保留控件的原始尺寸**，
##   所以这里显式写 anchors 与 offsets，控件才真正铺满整屏。

const MAX_ALPHA := 0.55     # 深夜最深的压暗程度（占位，可调）
const DUSK_START := 18.0    # 18:00 起开始变暗
const NIGHT_FULL := 21.0    # 21:00 达到最深
const DAWN_START := 5.0     # 05:00 起开始变亮
const DAWN_END := 7.0       # 07:00 完全恢复

var _last_alpha: float = -1.0

func _ready() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不吃鼠标，不挡点击
	color = Color(0, 0, 0, 0)
	TimeSystem.tick.connect(_on_tick)
	_refresh()

func _on_tick(_dt: float) -> void:
	_refresh()

func _refresh() -> void:
	var h := float(TimeSystem.hour()) + float(TimeSystem.minute()) / 60.0
	var k := 0.0
	if h >= DUSK_START and h < NIGHT_FULL:
		k = (h - DUSK_START) / (NIGHT_FULL - DUSK_START)        # 黄昏渐暗
	elif h >= NIGHT_FULL or h < DAWN_START:
		k = 1.0                                                  # 深夜
	elif h >= DAWN_START and h < DAWN_END:
		k = 1.0 - (h - DAWN_START) / (DAWN_END - DAWN_START)     # 黎明渐亮
	var a := k * MAX_ALPHA
	if not is_equal_approx(a, _last_alpha):
		_last_alpha = a
		color = Color(0, 0, 0, a)
