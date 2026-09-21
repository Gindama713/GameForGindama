extends Control

## 主角信息面板（2026-09-20）—— 从右侧滑出的「个人档案」。
##
## 【要解决什么】屏幕左下角的 PlayerHud 只够看血和需求；主角的**全身照 + 逐部位伤情**
##   需要一个更大的面板 —— 这才是"人"的视角（而不是"一只会动的棋子"）。
##
## 【布局】锚定屏幕右缘的一整条（TOP_RIGHT → BOTTOM_RIGHT），面板本体在条内**右对齐**。
##   滑出 = 把面板的 x 从"完全在屏外"缓动回 0；收回 = 反向。
##
## 【数据纪律】与 PlayerHud / 检视面板同一套：**只读通用组件**（Body / Needs / Aging / Lineage）。
##   本文件不认识"主角"或"猪" —— 换任何生物都能显示（只是它显示全身照需要该物种配了 art）。
##
## 【为什么全身照与部位按钮要"叠"在一起】用户要的是"点身上的手/头/腿" ——
##   所以部位按钮是**透明热区**，按解剖位置覆盖在全身照上，
##   而不是排成一列按钮（那样就不是"点身上"了）。热区位置来自 PART_LAYOUT。
##
## 【动画全部走 Tween】项目里首次使用 Tween。要点：
##   - **不要每帧 set_position**（那会和 Tween 打架）→ 只在开/关时 create_tween；
##   - 数值条（PixelBar）用**每帧阻尼插值**逼近目标（帧率无关的 exp 平滑），
##     因为血是会连续掉的，用 Tween 反而要不断打断重开。
##   - 部位切换用**交叉淡化**（旧详情淡出 → 换数据 → 淡入），避免"啪"地跳变。

# ---------------- 常量 ----------------

const PANEL_W := 300.0            # 面板宽度
const MARGIN := 8.0               # 与屏幕边缘的间距
const FONT_SIZE := 11             # 像素字体原生尺寸（与检视面板一致）
const TITLE_SIZE := 22            # 标题用 2 倍（像素字体只有整数倍不糊）
const CLOSE_SIZE := 22            # 右上角 × 的字号（与标题同档，够大能点但不臃肿）

const SLIDE_TIME := 0.28          # 滑出/收回时长（秒）
const FADE_TIME := 0.18           # 详情交叉淡化时长
const BAR_DAMP := 12.0            # 数值条阻尼（越大越跟手）

## 全身照显示高度（面板内）。person.png 是 512×512，等比缩到这么高。
const PORTRAIT_H := 300.0

## 部位热区布局：部位 id → 归一化矩形（x, y, w, h，相对全身照显示框 0..1）。
## **这是"美术知识"，不是"生物知识"** —— 即"这个物种的图里，头/手/腿画在哪个位置"。
## 所以它按物种配（放这里因为目前只有人形主角一例；将来多物种再抽成 def 字段）。
##
## 【2026-09-20 重算（问题4：框不贴合）】
##   ⚠ 旧值（head 0.40/0.01/0.20/0.17 等）是**目测拍的**，误差很大 —— 头框只到 y0.18，
##     而实测头一直画到 y0.30；腿框宽只有 0.10，实际两条腿合起来占 0.22。
##   现在**不再目测**：用脚本逐行扫描 `person.png` 的墨迹（alpha≥100 的白色线稿像素），
##   量出真实剪影，再按解剖分界换算成归一化坐标。依据（原图 512×512 像素）：
##     头部      y 23..152，最宽处 x 230..283（y=80）—— 肩线在 y=153 明显变宽
##     躯干(含臂) y 153..327，最宽 x 158..353（y≥293）—— 是件"下摆张开的袍身"
##     腿        y 328..488，x 201..312（y=328 处宽度从 196 骤降到 112）
##   ⚠ **这张图是"填充剪影"不是"线稿"**：没有手指缝、两腿之间也没有空隙（实测每行只有 1 段墨迹），
##     所以"左臂/右臂""左腿/右腿"是**按中轴 0.5 左右均分**的，不是按"两条独立的肢体"切 ——
##     图上它们本来就分不开。这是**素材的客观限制**，不是实现偷懒（详见 §5.9 素材台账）。
## 【2026-09-20 三改（问题2：左手右手之间要有躯干）】
##   旧值把 `arm_l` 取 0.309~0.500、`arm_r` 取 0.500~0.691 —— **两臂首尾相接**，
##   中间根本没有"躯干"这一区（胸腔虽然是 0.309~0.692 宽度，却和两臂完全重叠）。
##   用户要的是"左手和右手中间看得见一个躯干"，所以改成**内中外三段**：
##     中间芯 x0.391~0.609 = 躯干（胸腔）
##     左外带 x0.309~0.391 = 左臂
##     右外带 x0.609~0.691 = 右臂
##   ⇒ 臂是袍身的**外侧边band**，躯干是**中间芯**，三者互不重叠、并起来正好等于袍身全宽。
##   ⚠ 依据仍是实测（原图 512×512）：躯干最宽 x158..353（归一 0.309~0.690）。
##     这张图没有手臂缝（每行只有 1 段墨迹），所以"外侧 band = 臂"是**合理的近似**，
##     不是精确解剖 —— 但比"两臂对半分、中间没有躯干"更符合用户的直觉与点击预期。
const PART_LAYOUT := {
	"head":     Rect2(0.398, 0.041, 0.203, 0.264),   # 头 y0.041~0.305（实测 23..152，最宽 x206..304）
	"ribcage":  Rect2(0.391, 0.305, 0.219, 0.336),   # 躯干（**中间芯**）y0.305~0.641（实测 153..327）
	"arm_l":    Rect2(0.309, 0.312, 0.082, 0.326),   # 左臂（袍身**左外侧带**）
	"arm_r":    Rect2(0.609, 0.312, 0.082, 0.326),   # 右臂（袍身**右外侧带**）
	"leg_l":    Rect2(0.393, 0.641, 0.107, 0.314),   # 左腿 y0.641~0.955（实测 328..488）
	"leg_r":    Rect2(0.500, 0.641, 0.111, 0.314),   # 右腿
}

## 人体**轮廓多边形**（归一化坐标，相对全身照显示框）—— 问题4 的"轮廓描边可视化"。
##
## 【怎么来的】同样是脚本逐行扫描墨迹：取每 12px 一行的"最左/最右墨迹点"，
##   左边界自上而下、右边界自下而上，首尾相接成一条闭合轮廓。78 个点。
## 【为什么要它】用户要"检测框更贴合人体"。光把 6 个矩形调准还不够直观 ——
##   这条实测轮廓就是**人体的真实边界**，把热区叠在它上面，一眼能看出贴不贴合；
##   也让"框内的肢体到底有没有覆盖到"变成可视的（而不是只能靠猜）。
## 【为什么画在全身照之上而非替换全身照】轮廓是"辅助线"，不该盖掉美术本身：
##   用半透明的细线描边，既能校准视觉，又不喧宾夺主。
## 【注意：这里用 `var` 而不是 `const`】GDScript 的常量表达式求值器**不接受
##   `PackedVector2Array([...])` 这种构造调用**（实测报 "isn't a constant expression"）。
##   反正它是只读用途，用 `var` + 命名约定（全大写）即可，语义不变。
var SILHOUETTE := PackedVector2Array([
	Vector2(0.4805, 0.0449), Vector2(0.4414, 0.0684), Vector2(0.4238, 0.0918),
	Vector2(0.4121, 0.1152), Vector2(0.4062, 0.1387), Vector2(0.4023, 0.1621),
	Vector2(0.4023, 0.1855), Vector2(0.4062, 0.2090), Vector2(0.4141, 0.2324),
	Vector2(0.4258, 0.2559), Vector2(0.4453, 0.2793), Vector2(0.4199, 0.3027),
	Vector2(0.3770, 0.3262), Vector2(0.3574, 0.3496), Vector2(0.3457, 0.3730),
	Vector2(0.3359, 0.3965), Vector2(0.3301, 0.4199), Vector2(0.3242, 0.4434),
	Vector2(0.3203, 0.4668), Vector2(0.3164, 0.4902), Vector2(0.3145, 0.5137),
	Vector2(0.3105, 0.5371), Vector2(0.3105, 0.5605), Vector2(0.3086, 0.5840),
	Vector2(0.3086, 0.6074), Vector2(0.3086, 0.6309), Vector2(0.3926, 0.6543),
	Vector2(0.3945, 0.6777), Vector2(0.3965, 0.7012), Vector2(0.3984, 0.7246),
	Vector2(0.4004, 0.7480), Vector2(0.4023, 0.7715), Vector2(0.4043, 0.7949),
	Vector2(0.4043, 0.8184), Vector2(0.4062, 0.8418), Vector2(0.4082, 0.8652),
	Vector2(0.4102, 0.8887), Vector2(0.4121, 0.9121), Vector2(0.4141, 0.9355),
	Vector2(0.5918, 0.9355), Vector2(0.5938, 0.9121), Vector2(0.5957, 0.8887),
	Vector2(0.5977, 0.8652), Vector2(0.5996, 0.8418), Vector2(0.5996, 0.8184),
	Vector2(0.6016, 0.7949), Vector2(0.6035, 0.7715), Vector2(0.6055, 0.7480),
	Vector2(0.6074, 0.7246), Vector2(0.6074, 0.7012), Vector2(0.6094, 0.6777),
	Vector2(0.6113, 0.6543), Vector2(0.6914, 0.6309), Vector2(0.6914, 0.6074),
	Vector2(0.6914, 0.5840), Vector2(0.6914, 0.5605), Vector2(0.6895, 0.5371),
	Vector2(0.6895, 0.5137), Vector2(0.6875, 0.4902), Vector2(0.6836, 0.4668),
	Vector2(0.6797, 0.4434), Vector2(0.6758, 0.4199), Vector2(0.6699, 0.3965),
	Vector2(0.6602, 0.3730), Vector2(0.6484, 0.3496), Vector2(0.6309, 0.3262),
	Vector2(0.5898, 0.3027), Vector2(0.5547, 0.2793), Vector2(0.5723, 0.2559),
	Vector2(0.5840, 0.2324), Vector2(0.5918, 0.2090), Vector2(0.5957, 0.1855),
	Vector2(0.5957, 0.1621), Vector2(0.5918, 0.1387), Vector2(0.5859, 0.1152),
	Vector2(0.5742, 0.0918), Vector2(0.5566, 0.0684), Vector2(0.5117, 0.0449),
])

## 部位 id → 特写贴图。**未列出的部位不回退到全身照**（宁可显示"无特写"也不要误导）。
##
## 【为什么左右共用一张】现有素材（`arm.png` / `leg.png`）都是**单张居中的身体部件插画**，
##   不是左右成对的图。所以左右臂都指向同一张、左右腿也指向同一张 —— **不做水平翻转**
##   （翻转会让同一条手/腿看起来方向相反，反而像画错了）。
##   将来若要左右分明（比如伤口在左手），再给 `arm_l` / `arm_r` 各配一张。
const PART_TEXTURE := {
	"head": "res://creature/player/art/brain.png",      # 头（素材即头像/brain 插画）
	"ribcage": "res://creature/player/art/ribcage.png", # 胸腔
	"arm_l": "res://creature/player/art/arm.png",       # 左臂
	"arm_r": "res://creature/player/art/arm.png",       # 右臂（共用 arm.png）
	"leg_l": "res://creature/player/art/leg.png",       # 左腿
	"leg_r": "res://creature/player/art/leg.png",       # 右腿（共用 leg.png）
}
## 需要水平翻转的部位。**目前为空**：素材是单张居中的部件图，左右同源、无需镜像
##   （见 PART_TEXTURE 上方说明）。留着这个字典是为了"将来左右各配一张"时有地方写。
const PART_FLIP := {}

const PORTRAIT_TEX: Texture2D = preload("res://creature/player/art/person.png")

const ALIVE := Color(0.82, 0.82, 0.82)
const DIM := Color(0.42, 0.42, 0.42)
const WARN := Color(0.95, 0.55, 0.25)
const DEAD_C := Color(0.55, 0.2, 0.2)
const RING := Color(1.0, 1.0, 1.0)
## 轮廓描边色（比人物线稿亮一点、带透明度 —— 是"辅助线"不是"美术"）
const OUTLINE_COL := Color(0.45, 0.85, 1.0, 0.75)

## 伤势配色（2026-09-20 用户要求"手受伤会变颜色，轻微黄、重度红"）。
## 五档与 `BodyPart.Severity` **一一对应**，档位划分不在 UI 层重复定义。
## **完好档 = 纯白**：不要染色（染色会盖住美术本身的线条），
## 所以 `_severity_color` 对完好返回的是"不改变"的白色。
const SEV_COLOR := {
	BodyPart.Severity.HEALTHY:  Color(1.00, 1.00, 1.00),
	BodyPart.Severity.LIGHT:    Color(1.00, 0.88, 0.30),   # 轻伤：黄
	BodyPart.Severity.MODERATE: Color(1.00, 0.60, 0.10),   # 中度：橙
	BodyPart.Severity.SEVERE:   Color(0.95, 0.22, 0.18),   # 重伤：红
	BodyPart.Severity.DISABLED: Color(0.45, 0.08, 0.08),   # 失能：暗红
}
## 伤势中文名（与 SEV_COLOR 同序）。**用 BodyPart.severity_text()**，
## 这里不再重复一份 —— 避免两处文案走样。

# ---------------- 状态 ----------------

var _player: Creature = null

var _panel: PanelContainer
var _portrait: TextureRect
var _portrait_box: Control        # 定位容器（提供 PORTRAIT_H 高的参照系）
var _outline: Control             # 轮廓描边层（自绘，叠在全身照上；问题4）
var _hit_rects: Dictionary = {}   # part_id -> Button（透明热区，管点击+选中高亮）
var _tints: Dictionary = {}       # part_id -> ColorRect（伤势色块，管"受伤变色"）
var _selected := ""               # 当前选中部位 id（"" = 未选）

var _name_lbl: Label
var _info_lbl: Label
var _close_btn: Button
var _hp_bar: PixelBar
var _hp_lbl: Label
var _detail_title: Label
var _detail_tex: TextureRect
var _detail_bar: PixelBar
var _detail_lbl: Label
var _detail_section: VBoxContainer
var _need_rows: Array = []        # {need, bar}
var _needs_grid: GridContainer

var _open := false
var _tween: Tween = null
var _hide_tween: Tween = null      # 收起动画结束后 hide 的计时（与 _tween 分开，互不打断）
var _fade_tween: Tween = null

# —— 拖拽（问题3）——
var _dragging := false
var _drag_off := Vector2.ZERO     # 鼠标按下时相对面板左上角的偏移
var _manual_pos := false          # 用户拖动过 → 之后不再被滑出动画强制归位

# 数值条阻尼用（帧率无关的指数平滑）
var _hp_shown := 1.0
var _need_shown: Array = []       # 与 _need_rows 平行
var _detail_shown := 1.0          # 选中部位的血条显示值（同样阻尼）

func _ready() -> void:
	_build()
	# 自己订阅 —— 与 PlayerHud 同一套路（Main 不必记得喂这个面板）
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.creature_died.connect(_on_creature_died)
	EventBus.creature_clicked.connect(_on_creature_clicked)
	TimeSystem.tick.connect(_on_tick)
	# 收在屏外（不占屏、也不吃输入）
	_snap_closed()

## 点到自己 = 打开自己的档案（2026-09-20 用户要求）。
##
## 【判定口径：不看名字、不加 is_player 字段】用**引用比对** `c == _player` ——
##   `_player` 是 `Main` 发 `player_spawned` 时给的，谁在扮演玩家由编排层决定，
##   面板只认"这是不是那只被指派的主角"。于是换任何物种当主角都不用改这里。
## 【为什么主动接管】否则点主角会走通用检视窗（那是给"观察别的生物"用的调试面板），
##   而玩家想看的是自己的全身照档案 —— 两件事，两个窗口。
func _on_creature_clicked(c: Node) -> void:
	if _player == null or c != _player:
		return
	open_panel()

## **B** = 开关面板（2026-09-20 按用户要求从 Tab 改为 B）。
##
## 【为什么用 `physical_keycode`】与 WASD 同一套纪律（事实文档 §4.5）：按**物理键位**判定，
##   布局无关（AZERTY / Dvorak 上按的还是同一个物理键）。
## 【为什么用 `_unhandled_key_input` 而不是 InputMap】这是一次性 UI 开关，不需要"按下/按住"语义，
##   也不该进 `project.godot` 的 `[input]`（那里是移动键的地盘）。**未消费的按键**才走到这里。
func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_B:
		toggle()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	# 数值条阻尼：血会连续掉，用 Tween 要不断打断重开，不如每帧逼近
	if not _open or _player == null:
		return
	var k := 1.0 - exp(-BAR_DAMP * dt)
	_hp_shown = lerpf(_hp_shown, _target_hp_ratio(), k)
	_hp_bar.set_ratio(_hp_shown)
	for i in _need_rows.size():
		if i >= _need_shown.size():
			break
		_need_shown[i] = lerpf(_need_shown[i], (_need_rows[i]["need"] as Need).ratio(), k)
		(_need_rows[i]["bar"] as PixelBar).set_ratio(_need_shown[i])
	# 选中部位的血条 —— **同样走阻尼**（2026-09-20 修：之前这条根本没被更新过，
	# 所以无论怎么受伤都停在 0/60 的空条上）。
	# 只在选中且有该部位时才逼近，否则会把数字拉到无关的目标上。
	if _selected != "":
		var part := _selected_part()
		if part != null:
			_detail_shown = lerpf(_detail_shown, part.ratio(), k)
			_detail_bar.set_ratio(_detail_shown)
	# 轮廓描边随窗口变化重画（尺寸变了锚点会变）
	if _outline != null:
		_outline.queue_redraw()

# ---------------- 构建 ----------------

func _build() -> void:
	# 本控件铺满整个屏幕（只用来定位；mouse_filter=IGNORE 让别处照常收输入）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 面板本体吃输入（不穿透点到世界）
	_panel.custom_minimum_size.x = PANEL_W
	add_child(_panel)

	# —— 外层边距（文字不贴面板边框）——
	# 关闭 × 的位置**不能交给 HBox 排版**（会被标题/时钟挤到中间）；见下方 overlay 说明。
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(pad)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pad.add_child(vb)

	# —— 标题行：名字 +（**末尾留一块空白给右上角的 ×**，不然会被压住）——
	# 标题行同时是**拖拽把手**（问题3）：见 _gui_input 接线。
	# ⚠ 时刻显示已移除（问题4）：屏幕顶部本就有时钟，这里再放一个是重复的。
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_default_cursor_shape = Control.CURSOR_DRAG
	head.tooltip_text = "按住拖动面板"
	head.gui_input.connect(_on_title_gui_input)
	vb.add_child(head)
	_name_lbl = _label("", TITLE_SIZE)
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 让拖拽不被 Label 吃掉
	head.add_child(_name_lbl)
	var head_spacer := Control.new()          # 给悬浮 × 让位（宽 = × 宽 + 余量）
	head_spacer.custom_minimum_size.x = CLOSE_SIZE + 8
	head_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_spacer)

	# —— 右上角 × 用**铺满整块面板的定位层**承载 ——
	# ⚠ 关键坑：`PanelContainer` 会把**直接子节点**摆到内容区（受主题边距约束），
	#   所以在 _panel 上直接挂一个锚 TOP_RIGHT 的 Button 是**没用**的 ——
	#   实测它被放到 x=8（内容区左上），而不是右上角。
	#   解法：中间垫一层 `Control`（PRESET_FULL_RECT），锚点才是相对**整块面板**算的。
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 只当定位参照，不吃输入
	_panel.add_child(overlay)

	# —— 右上角关闭 ×（悬浮在内容之上）——
	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.flat = true
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_btn.tooltip_text = "关闭（B）"
	_close_btn.add_theme_font_size_override("font_size", CLOSE_SIZE)
	_close_btn.add_theme_constant_override("padding_left", 2)
	_close_btn.add_theme_constant_override("padding_right", 2)
	_close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.offset_left = -(CLOSE_SIZE + 10)
	_close_btn.offset_top = 2
	_close_btn.offset_right = -4
	_close_btn.offset_bottom = CLOSE_SIZE + 8
	_close_btn.pressed.connect(close_panel)
	overlay.add_child(_close_btn)

	# —— 性别 · 年龄 · 阶段 ——
	_info_lbl = _label("", FONT_SIZE)
	vb.add_child(_info_lbl)

	# —— 全身照 + 部位热区（叠在一起）——
	var portrait_wrap := CenterContainer.new()
	vb.add_child(portrait_wrap)
	_portrait_box = Control.new()
	_portrait_box.custom_minimum_size = Vector2(PORTRAIT_H, PORTRAIT_H)
	_portrait_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_wrap.add_child(_portrait_box)

	_portrait = TextureRect.new()
	_portrait.texture = PORTRAIT_TEX
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_box.add_child(_portrait)

	_build_hit_rects()

	# —— 轮廓描边（问题4）：**必须最后加** —— 画在所有热区/色块之上，
	#    否则会被色块盖住（CanvasItem 按子节点顺序画，后加的在上）。
	_outline = Control.new()
	_outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.draw.connect(_draw_outline)
	_portrait_box.add_child(_outline)

	# —— 总血 ——
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	vb.add_child(hp_row)
	hp_row.add_child(_label("生命", FONT_SIZE))
	_hp_bar = PixelBar.new()
	_hp_bar.segments = 12
	hp_row.add_child(_hp_bar)
	_hp_lbl = _label("", FONT_SIZE)
	hp_row.add_child(_hp_lbl)

	# —— 需求 ——
	_needs_grid = GridContainer.new()
	_needs_grid.columns = 2
	_needs_grid.add_theme_constant_override("h_separation", 10)
	_needs_grid.add_theme_constant_override("v_separation", 3)
	vb.add_child(_needs_grid)

	# —— 部位详情（默认隐藏；点部位后显示）——
	_detail_section = VBoxContainer.new()
	_detail_section.add_theme_constant_override("separation", 3)
	_detail_section.visible = false
	vb.add_child(_detail_section)
	_detail_title = _label("", FONT_SIZE)
	_detail_section.add_child(_detail_title)
	_detail_tex = TextureRect.new()
	_detail_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_tex.custom_minimum_size = Vector2(PANEL_W - 40, 150)
	_detail_section.add_child(_detail_tex)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	_detail_section.add_child(drow)
	_detail_bar = PixelBar.new()
	_detail_bar.segments = 12
	drow.add_child(_detail_bar)
	_detail_lbl = _label("", FONT_SIZE)
	drow.add_child(_detail_lbl)

## 按 PART_LAYOUT 建热区（叠在全身照上）。
##
## 【每格两层】
##   ① `ColorRect` 伤势色块 —— **这就是"受伤时身体会变色"**：色块按部位形状铺在全身照对应位置，
##      颜色由 `SEV_COLOR[severity]` 给；`mouse_filter = IGNORE` 不挡点击。
##   ② `Button` 透明热区 —— 只负责点击，`modulate` 用来自绘"选中高亮"。
## 为什么不合成一个控件：色块要**纯色填充**、按钮要**吃点击**，两者职责不同；
##   分开后"高亮变色"与"伤势变色"互不干扰（按钮 modulate 只管选中，色块只管伤势）。
func _build_hit_rects() -> void:
	for pid in PART_LAYOUT.keys():
		var r: Rect2 = PART_LAYOUT[pid]
		var al: float = r.position.x
		var at: float = r.position.y
		var ar: float = r.position.x + r.size.x
		var ab: float = r.position.y + r.size.y

		var tint := ColorRect.new()
		tint.color = Color(1, 1, 1, 0)          # 完好 = 全透明（不染色）
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tint.anchor_left = al; tint.anchor_top = at
		tint.anchor_right = ar; tint.anchor_bottom = ab
		tint.offset_left = 0; tint.offset_top = 0; tint.offset_right = 0; tint.offset_bottom = 0
		_portrait_box.add_child(tint)
		_tints[pid] = tint

		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# 归一化 → 像素（锚定比例，随 _portrait_box 尺寸自适应）
		hit.anchor_left = al; hit.anchor_top = at
		hit.anchor_right = ar; hit.anchor_bottom = ab
		hit.offset_left = 0; hit.offset_top = 0; hit.offset_right = 0; hit.offset_bottom = 0
		hit.pressed.connect(_on_part_pressed.bind(pid))
		_portrait_box.add_child(hit)
		_hit_rects[pid] = hit

## 画人体轮廓 + 六个热区的边框（问题4 的"轮廓描边可视化"）。
##
## 【画什么】
##   ① 实测剪影轮廓（SILHOUETTE，青色半透明闭合线）—— 人体的真实边界；
##   ② 六个热区边框（选中=亮白、未选中=暗灰虚线感）—— 一眼看出框有没有包住肢体。
## 这样"框贴不贴合"是**看得见的**，而不是只能靠运行起来点一点试试。
func _draw_outline() -> void:
	if _outline == null:
		return
	var s := _outline.size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	# ① 剪影轮廓
	var pts := PackedVector2Array()
	for p in SILHOUETTE:
		pts.append(Vector2(p.x * s.x, p.y * s.y))
	pts.append(pts[0])                     # 闭合
	_outline.draw_polyline(pts, OUTLINE_COL, 1.5, true)
	# ② 热区边框
	for pid in PART_LAYOUT.keys():
		var r: Rect2 = PART_LAYOUT[pid]
		var rect := Rect2(r.position.x * s.x, r.position.y * s.y,
			r.size.x * s.x, r.size.y * s.y)
		var sel: bool = (pid == _selected)
		var col := Color(1, 1, 1, 0.85) if sel else Color(0.6, 0.6, 0.6, 0.35)
		_outline.draw_rect(rect, col, false, 1.0)

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)   # 父主题不继承，必须逐控件设
	return l

# ---------------- 拖拽（问题3） ----------------

## 标题栏拖动面板。
##
## 【为什么挂在标题行而不是整个面板】要点部位热区（那也是一堆按钮）——
##   把整个面板都变成拖动区会让"点部位"变成"拖着面板走"。标题行是**天然的把手**。
## 【为什么用 _gui_input 而不是 _input】_gui_input 只在**鼠标落在该控件上**时触发，
##   天然就把"拖面板"和"点世界里的生物"分开了（后者走 Creature._unhandled_input）。
## 【拖动后不再自动归位】`_manual_pos = true` → 滑出/收起动画跳过 x 归零，
##   否则用户好不容易拖到顺手的位置，一收一开又弹回右边缘。
func _on_title_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_off = mb.global_position - _panel.global_position
				_kill_tween()
			else:
				_dragging = false
				_manual_pos = true
	elif ev is InputEventMouseMotion and _dragging:
		var m := ev as InputEventMouseMotion
		_panel.global_position = m.global_position - _drag_off
		_clamp_panel()

## 让面板至少留一部分在屏幕内（拖不丢）。
func _clamp_panel() -> void:
	var vp := get_viewport_rect().size
	var p := _panel.global_position
	p.x = clampf(p.x, -PANEL_W + 80.0, vp.x - 60.0)
	p.y = clampf(p.y, 0.0, maxf(vp.y - 40.0, 0.0))
	_panel.global_position = p

# ---------------- 开 / 关（Tween 滑出） ----------------

func _on_player_spawned(c: Node) -> void:
	_player = c as Creature
	_rebuild()
	open_panel()

func toggle() -> void:
	if _open:
		close_panel()
	else:
		open_panel()

func is_open() -> bool:
	return _open

func open_panel() -> void:
	if _player == null:
		return
	_set_open(true)

func close_panel() -> void:
	_set_open(false)

## 开关面板。**两条并行动画**让动作"丝滑"而不是"啪"地拍进去：
##   ① 位移：`position:x` 从屏外滑入（`TRANS_BACK`/`EASE_OUT` = 末尾一点点回弹，有"停住"的重量感）
##   ② 透明度：`modulate:a` 同步淡入淡出（消除"边缘硬切进画面"的突兀感）
## 收回时用 `TRANS_CUBIC`/`EASE_IN`（起步慢、收尾快）—— 开与关用不同曲线，
##   因为"进入"要果决、"退出"要轻快，同一条曲线两边都别扭。
## 【拖拽兼容】若用户手动拖过（`_manual_pos`），滑出动画**只做淡入淡出、不动位置** ——
##   尊重用户摆的位置，不被动画抢走。
##
## 【问题3 的根因，2026-09-20 修】**收起时必须停止吃输入**。
##   之前收起只是 `modulate.a = 0` + 把 x 推到 `PANEL_W + MARGIN (=308)` ——
##   但面板本体宽 336，于是它**仍然占着屏幕上 x308~644 的一条竖带**，
##   而且是 `mouse_filter = STOP`：肉眼看不见，却把落在那一带的所有点击**全吃掉**。
##   ⇒ 现象就是"点了一次关了就打不开了"：那一片的猪永远点不中，
##     看起来就像"检视窗坏了"。修法：收起时把 `mouse_filter` 设为 IGNORE（不挡点击），
##     并在动画结束、彻底滑出屏外后 `hide()`；打开时再恢复 STOP。
func _set_open(v: bool) -> void:
	if _open == v:
		return
	_open = v
	_kill_tween()
	_kill_hide_tween()             # 取消上一次"收完再 hide"的计时（连点 B 时别把刚开的面板又藏了）
	# 打开：立刻可交互；收起：立刻停止吃输入（**不要等动画跑完**，否则动画期间仍在吞点击）
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
	if v:
		_panel.show()                  # 收起后才 hide 的，打开要显形
	_tween = create_tween().set_parallel(true)
	if v:
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_tween.tween_property(_panel, "modulate:a", 1.0, SLIDE_TIME * 0.7)
		if not _manual_pos:
			_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_panel, "position:x", 0.0, SLIDE_TIME)
	else:
		_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_property(_panel, "modulate:a", 0.0, SLIDE_TIME * 0.6)
		if not _manual_pos:
			_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			_tween.tween_property(_panel, "position:x", PANEL_W + MARGIN, SLIDE_TIME * 0.8)
		# 动画跑完再 hide（彻底不参与绘制与输入）。用户拖过面板时不动位置，
		# 但依然要 hide —— 否则那块"看不见的挡板"会一直留在屏幕上。
		# ⚠ 用**独立的串行 Tween** 挂结束回调：并行 Tween 上 `chain()` 的语义易混，
		#   单开一条只做"等一下再回调"的串行 Tween 最直白、也不会被 parallel 影响。
		_hide_tween = create_tween()
		_hide_tween.tween_interval(SLIDE_TIME * 0.8)
		_hide_tween.tween_callback(_on_close_anim_done)

## 收起动画结束 → 真正藏起来（隐藏的 Control 不吃输入、不绘制，问题3 的彻底修法）。
func _on_close_anim_done() -> void:
	if not _open:
		_panel.hide()

## 立刻放在"关闭"位置（无动画）—— _ready 时用，避免开局看到面板飞出来。
## ⚠ 同样要**停止吃输入**（见 _set_open 的说明）：开局面板就是收起的，
##   若它保持 STOP，屏幕右中那条带从第一帧起就点不穿。
func _snap_closed() -> void:
	await get_tree().process_frame     # 等布局算完，size 才准
	_panel.position.x = PANEL_W + MARGIN
	_panel.modulate.a = 0.0            # 与 _set_open 的淡入对齐（否则首帧是"不透明地在屏外"）
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 注意：**不 hide()** —— hide 之后 `_process` 里的阻尼与节点结构仍可用，
	#   但 _ready 时 hide 会让"开局自动打开"（_on_player_spawned → open_panel）时
	#   还得多写一次 show。这里靠 mouse_filter 已经足够不打扰输入，
	#   而开局 open_panel() 会把 mouse_filter 复原。
	#   但如果开局就保持"看不见却存在"，仍会绘制一份完全透明的 336×707 面板（纯浪费），
	#   所以在 player 生成之前先 hide 掉（open_panel 会 show 回来）。
	if not _open:
		_panel.hide()

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

func _kill_hide_tween() -> void:
	if _hide_tween != null and _hide_tween.is_valid():
		_hide_tween.kill()

# ---------------- 选中部位 ----------------

func _on_part_pressed(pid: String) -> void:
	if _player == null:
		return
	# 再点同一部位 = 取消选中
	_selected = "" if _selected == pid else pid
	_refresh_detail(true)

## `animated` = 是否交叉淡化（点头时为 true；每 tick 刷新时为 false）
func _refresh_detail(animated: bool) -> void:
	var part := _selected_part()
	if _selected == "" or part == null:
		_detail_section.visible = false
		_update_highlights()
		return
	# 血条不走"从当前值滑到目标"，而是**直接跳到新部位的当前值** ——
	# 否则从"满血的腿"切到"空血的腿"会看到条从满滑到空，像刚受了伤，是假信息。
	_detail_shown = part.ratio()
	_detail_bar.set_ratio(_detail_shown)

	var apply := func() -> void:
		_detail_title.text = "%s · %s" % [part.def.label, part.severity_text()]
		_detail_title.add_theme_color_override("font_color", _severity_color(part))
		var path: String = PART_TEXTURE.get(_selected, "")
		_detail_tex.texture = load(path) if not path.is_empty() else null
		# 左右镜像（左臂/左腿共用右侧那张素材 —— 目前 PART_FLIP 为空，见其说明）
		_detail_tex.flip_h = PART_FLIP.get(_selected, false)
		# 特写图也按伤势染色 —— 与全身照上的色块同一把尺子
		_detail_tex.self_modulate = _severity_color(part)
		_detail_section.visible = true
		_update_highlights()

	if not animated:
		apply.call()
		return
	# 交叉淡化：先淡出 → 换内容 → 淡入（不重建控件，只动 modulate）
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_detail_section, "modulate:a", 0.0, FADE_TIME * 0.5)
	_fade_tween.tween_callback(apply)
	_fade_tween.tween_property(_detail_section, "modulate:a", 1.0, FADE_TIME * 0.5)

## 高亮选中的热区（其余压暗）—— 用边框色 + 轻微缩放脉冲。
func _update_highlights() -> void:
	for pid in _hit_rects.keys():
		var hit: Button = _hit_rects[pid]
		var sel: bool = (pid == _selected)   # 显式标注：Dictionary 取出的是 Variant
		# 选中：边缘脉冲（Tween）；未选中：回到常态
		var t := create_tween()
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(hit, "self_modulate",
			RING if sel else Color(1, 1, 1, 0.0), 0.16)

## 按 **每个部位各自的伤势** 给全身照上的色块上色（"受伤了身体会变色"）。
##
## 【为什么不合并成"整体一色"】用户要的是"手受伤了**手**会变颜色" ——
##   伤在哪就染在哪，一眼能看出是哪条肢体出了问题。所以是**逐部位**判断。
## 【完好 = 全透明】不是画一个白色块：白色会盖住人物线条（素材是黑色线稿）。
##   透明度随伤势加深而提高，这样轻伤是"淡淡一层黄"、重伤才是"实红"。
func _update_tints() -> void:
	var body := _player.get_component(Body) as Body if _player != null else null
	for pid in _tints.keys():
		var rect: ColorRect = _tints[pid]
		var part := _part_by_id(body, pid)
		if part == null:
			rect.color = Color(1, 1, 1, 0)
			continue
		var c := _severity_color(part)
		c.a = _sev_alpha(part.severity(), part.bleeding > 0.0)
		rect.color = c

## 伤势档 → 色块不透明度。**唯一入口**：全身照色块与特写染色都问它，不各自写一套阈值。
## 完好档 = 0（不染色）；其余 0.18（轻）→ 0.58（失能）；出血再叠一点，让"正在掉血"更醒目。
func _sev_alpha(sev: int, bleeding: bool) -> float:
	var a := 0.0
	match sev:
		BodyPart.Severity.LIGHT:    a = 0.18
		BodyPart.Severity.MODERATE: a = 0.32
		BodyPart.Severity.SEVERE:   a = 0.46
		BodyPart.Severity.DISABLED: a = 0.58
	if bleeding and a > 0.0:
		a = minf(a + 0.12, 0.75)
	return a

# ---------------- 刷新（每 tick） ----------------

func _on_tick(_dt: float) -> void:
	if not _open or _player == null:
		return
	if not is_instance_valid(_player):
		close_panel()
		return
	_refresh()

## 重建（换主角 / 部位集变化时）—— 全量建控件树
func _rebuild() -> void:
	if _player == null:
		return
	# 姓名
	_name_lbl.text = _player.def.display_name if _player.def != null else "?"
	# 需求格（数据驱动：主角挂哪几条就显示哪几条）
	for ch in _needs_grid.get_children():
		ch.queue_free()
	_need_rows.clear()
	_need_shown.clear()
	var needs := _player.get_component(Needs) as Needs
	if needs != null:
		for n in needs.needs:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 1)
			cell.add_child(_label(n.def.label, FONT_SIZE))
			var bar := PixelBar.new()
			bar.segments = 10
			cell.add_child(bar)
			_needs_grid.add_child(cell)
			_need_rows.append({"need": n, "bar": bar})
			_need_shown.append(n.ratio())
	_hp_shown = _target_hp_ratio()
	_detail_shown = 1.0
	_detail_section.visible = false
	_selected = ""
	_refresh()

## 只改数值（不重建控件树）
func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 信息行：性别 · 年龄 · 阶段
	var ag := _player.get_component(Aging) as Aging
	var lin := _player.get_component(Lineage) as Lineage
	var bits: Array[String] = []
	if lin != null:
		bits.append("性别 %s" % lin.sex_text())
	if ag != null:
		bits.append("第 %.1f 天" % TimeSystem.minutes_to_days(ag.age_min))
		bits.append("「%s」" % ["幼年", "成年", "老年"][ag.stage()])
	_info_lbl.text = " · ".join(bits)

	# 标题行的时钟（与顶部 TimeDisplay 同一口径：「第 N 天 HH:MM」）
	# 总血（数值由 _process 阻尼逼近，这里只写文字与目标）
	var body := _player.get_component(Body) as Body
	if body != null:
		_hp_lbl.text = "%d/%d" % [int(body.total_hp()), int(body.total_max())]

	# **全身照按伤势上色**（每 tick 都跟，伤情一变颜色就变）
	_update_tints()

	# 部位详情里的条与文字（数值同样在 _process 里阻尼）
	if _selected != "":
		var part := _selected_part()
		if part != null:
			_detail_lbl.text = "%d/%d · %s" % [
				int(part.hp), int(part.def.max_hp), part.severity_text()]
			var c := _severity_color(part)
			_detail_title.add_theme_color_override("font_color", c)
			_detail_tex.self_modulate = c
			# 标题文案也要跟着伤势变（可能从"轻伤"变"失能"）
			var want := "%s · %s" % [part.def.label, part.severity_text()]
			if _detail_title.text != want:
				_detail_title.text = want

	# 主角死了 → 面板切红
	if not _player.is_alive():
		_name_lbl.add_theme_color_override("font_color", DEAD_C)

func _target_hp_ratio() -> float:
	if _player == null:
		return 0.0
	var body := _player.get_component(Body) as Body
	if body == null:
		return 0.0
	var mx := body.total_max()
	return body.total_hp() / mx if mx > 0.0 else 0.0

## 当前选中部位的 BodyPart（未选中 / 主角无 Body / 部位不存在 → null）。
func _selected_part() -> BodyPart:
	if _player == null or _selected == "":
		return null
	return _part_by_id(_player.get_component(Body) as Body, _selected)

## 「按 id 找部位」的唯一定义域在 `Body.part_by_id()`（§4.5）。
## ⚠ 这里**不重复实现**查找遍历 —— 以前本文件自己写过一份一样的循环，
##   那正是"同一个口径写两遍就会分叉"的老病（详见 `Grazing.can_eat_here()` 的踩坑记录）。
## 本函数只负责"把 null 收成 null"，不负责"怎么找"。
func _part_by_id(body: Body, pid: String) -> BodyPart:
	if body == null:
		return null
	return body.part_by_id(pid)

## 伤势 → 颜色。**唯一入口**：色块、特写、标题都问它，不各自写一套阈值。
func _severity_color(part: BodyPart) -> Color:
	return SEV_COLOR.get(part.severity(), ALIVE)

func _on_creature_died(c: Node) -> void:
	if c != _player:
		return
	_refresh()
