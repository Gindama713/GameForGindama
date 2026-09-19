extends Label

## 顶部中央时钟：显示「第 N 天  HH:MM」。时间来自 TimeSystem（Autoload）。
## 【纪律】只读 TimeSystem，不持有任何游戏状态。
## 只在显示文本真的变化时才写 text —— 一游戏分钟才变一次，不必每帧重排。

var _last_text: String = ""

func _ready() -> void:
	# 通栏 + 水平/垂直居中。**必须显式写 anchors 与 offsets**：
	# 实测 `set_anchors_preset()` 会把控件尺寸按当前文本宽度保留（只有 ~163px 宽、贴在左边），
	# 于是 horizontal_alignment=CENTER 只在那个窄盒子里居中 → 文字跑到左上角。
	# 把 offset_left / offset_right 归零，控件才真正横跨整个视口、文字落在正中。
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0
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
