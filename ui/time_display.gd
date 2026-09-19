extends Label

## 顶部中央时钟：显示「第 N 天  HH:MM」。时间来自 TimeSystem（Autoload）。
## 【纪律】只读 TimeSystem，不持有任何游戏状态。
## 只在显示文本真的变化时才写 text —— 一游戏分钟才变一次，不必每帧重排。

var _last_text: String = ""

func _ready() -> void:
	# 顶边通栏 + 水平居中：文本变宽也不会偏（不用 MINSIZE，免得改字后不重新居中）
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = 8.0
	offset_bottom = 44.0
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 不吃鼠标：否则顶部整条会挡住点击（选生物 / 操作面板）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TimeSystem.tick.connect(_on_tick)
	_refresh()

func _on_tick(_dt: float) -> void:
	_refresh()

func _refresh() -> void:
	var s := TimeSystem.day_time_string()
	if s != _last_text:
		_last_text = s
		text = s
