extends Control

## 主角 HUD（2026-09-20）—— 屏幕上"看得见主角本人 + 他的需求状态"。
##
## 【纪律】与检视面板同一套取数方式：**只读通用组件**（`get_component(Needs/Body/Aging/Lineage)`），
##   不认识"猪 / 主角"这类具体物种 —— 换成任何生物都能显示。
##
## 【为什么每 tick 全量刷新而不是逐项增删】HUD 元素是**固定 4 条需求 + 1 条总血**（主角的需求集不随时间变），
##   所以 `_build()` 一次建好、`_refresh()` 只改数值，不重建控件树（检视面板要重建是因为它会在物种间切换）。
##   ⚠ 只在**文本/比例真的变了**才写控件 —— 避免每帧触发无谓的 queue_redraw 与重排。

## 主角需求显示顺序与中文名。**不是硬编码组件**：按 id 问 Needs 要，缺哪条就不显示哪条。
const NEED_ORDER: Array[String] = [NeedIds.FOOD, NeedIds.WATER, NeedIds.WARMTH, NeedIds.FATIGUE]
const NEED_COLS := 2           # 需求 2 列 × 2 行（左右不再挤成一条长龙）

const BAR_SEGMENTS := 10       # 每条需求/总血的像素条段数
const FONT_SIZE := 11          # 小字（像素字体 11px 原生；父控件覆盖不继承，必须逐控件设）

## 与屏幕边缘的间距。**必须自己留**：底左锚点若把控件贴到 y=768 再让内容往下长，
##   多出来的部分就落到屏幕外（问题4："左下角多出来个什么，画面装不下了"）。
const MARGIN := 8.0

var _player: Creature = null

var _root: VBoxContainer
var _total_bar: PixelBar
var _total_lbl: Label
## 体力条（2026-09-21）。**不是**一条需求 —— 它归 `Sprint` 组件管，且上限是动态的。
var _stamina_bar: PixelBar
var _stamina_lbl: Label
var _needs_grid: GridContainer
var _age_lbl: Label
## 睡眠状态行（2026-09-21）。**必须有** —— 睡着时时间在加速，
## 不说明白的话玩家只会看到"画面突然变快、角色不动"。
var _sleep_lbl: Label
var _dead_lbl: Label
var _need_rows: Array = []     # {need: Need, bar: PixelBar}

func _ready() -> void:
	_build()
	TimeSystem.tick.connect(_on_tick)
	# 自己订阅主角生成 —— 不必让 Main 记得"生成后还要喂 HUD 一口"（少一处接线疏漏）。
	EventBus.player_spawned.connect(_on_player_spawned)
	# 死亡走通用的 creature_died（**死亡内核零改动**：die() 本就广播它），收到后按引用过滤。
	EventBus.creature_died.connect(_on_creature_died)
	visible = false            # 没有主角时不占屏（调试壳阶段 UI 要干净）

func _build() -> void:
	# —— 左下角 ——
	# ⚠ 关于"画面装不下"（问题4）：锚在左下角的控件，若把锚点放在 y=768 再让内容**向下**长，
	#   面板会超出屏幕底边（实测旧版底边到 834，超屏 66px）。
	#   这里改用最直白也最稳的办法：锚在**左下角**，但**每次布局完都把整块面板上推到 MARGIN 以上**
	#   （见 _fit_to_screen），不依赖容器的 SIZE_* 标志去猜。
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = MARGIN
	offset_top = -MARGIN
	offset_right = MARGIN
	offset_bottom = -MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # HUD 只看不点，不抢鼠标

	var panel := PanelContainer.new()
	panel.name = "HudPanel"
	add_child(panel)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 4)
	panel.add_child(_root)

	# —— 总血行 ——
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	_root.add_child(hp_row)
	hp_row.add_child(_small("生命"))
	_total_bar = PixelBar.new()
	_total_bar.segments = BAR_SEGMENTS
	hp_row.add_child(_total_bar)
	_total_lbl = _small("")
	hp_row.add_child(_total_lbl)

	# —— 体力行（2026-09-21）——
	# 【为什么单独一行、不塞进下面的需求格】体力**不是一条需求**：它归 `Sprint` 组件管，
	#   而且**上限是动态的**（= 疲劳值）。塞进 `_needs_grid` 会让人以为它和饥饿/口渴是同一类东西，
	#   也会让"上限在缩"这件事看不出来。这里显示成 `当前/上限` 两个数，缩了就直接看得见。
	var st_row := HBoxContainer.new()
	st_row.add_theme_constant_override("separation", 8)
	_root.add_child(st_row)
	st_row.add_child(_small("体力"))
	_stamina_bar = PixelBar.new()
	_stamina_bar.segments = BAR_SEGMENTS
	st_row.add_child(_stamina_bar)
	_stamina_lbl = _small("")
	st_row.add_child(_stamina_lbl)

	# —— 需求行（4 列 × 1 行）——
	_needs_grid = GridContainer.new()
	_needs_grid.name = "HudNeedsGrid"
	_needs_grid.columns = NEED_COLS
	_needs_grid.add_theme_constant_override("h_separation", 8)
	_needs_grid.add_theme_constant_override("v_separation", 3)
	_root.add_child(_needs_grid)

	# —— 睡眠状态（默认隐藏，只在非清醒时出现）——
	_sleep_lbl = _small("")
	_sleep_lbl.visible = false
	_root.add_child(_sleep_lbl)

	# —— 年龄 / 阶段 / 性别 ——
	_age_lbl = _small("")
	_root.add_child(_age_lbl)

	# —— 死亡提示（默认隐藏）——
	_dead_lbl = _small("")
	_dead_lbl.visible = false
	_root.add_child(_dead_lbl)

## 主角生成 —— 由 EventBus.player_spawned 触发。Main 不需要认识 HUD。
func _on_player_spawned(c: Node) -> void:
	_bind(c as Creature)

## 把整块 HUD **上推到屏内**（问题4）。锚点在左下角时，内容会向下溢出屏幕底边；
## 这里在每次布局算完后，把面板的 y 提到 `viewport高 - 面板高 - MARGIN`。
## ⚠ 用 `call_deferred` / 等一帧：`size` 要等容器排版跑完才准，立刻读会是 0。
func _fit_to_screen() -> void:
	await get_tree().process_frame
	var panel := get_node_or_null("HudPanel") as Control
	if panel == null:
		return
	var vp := get_viewport_rect().size
	# 面板高度以**实际内容**为准（容器最小尺寸），不靠父控件
	var h := maxf(panel.get_combined_minimum_size().y, panel.size.y)
	# 面板锚左下角，所以往上推 = 给一个负的 offset_top，同时 offset_bottom 补足高度
	offset_top = -MARGIN - h
	offset_bottom = -MARGIN
	# 宽度同理：让面板贴左边、只占内容宽（不铺满屏幕）
	var w := maxf(panel.get_combined_minimum_size().x, panel.size.x)
	offset_right = MARGIN + w
	if h > vp.y - MARGIN * 2.0:
		push_warning("[HUD] 面板高 %.0f 超过屏幕可用高度 %.0f，可能仍被裁切" % [h, vp.y - MARGIN * 2.0])

## 绑定主角（也可直接调用；与 camera.set_target 并列的"HUD 侧唯一切入点"）。
func set_player(c: Creature) -> void:
	_bind(c)

func _bind(c: Creature) -> void:
	_player = c
	if c == null:
		visible = false
		return
	_build_need_rows()
	_refresh()
	visible = true
	_fit_to_screen()

## 按主角**实际挂的需求**建格子（数据驱动：换个物种需求集不同也不会错位）。
## `NEED_ORDER` 里有、但主角没挂的（如没挂 fatigue）→ 跳过不显示。
func _build_need_rows() -> void:
	for child in _needs_grid.get_children():
		child.queue_free()
	_need_rows.clear()
	var needs := _player.get_component(Needs) as Needs
	if needs == null:
		return
	for id in NEED_ORDER:
		var n := needs.need_by_id(id)
		if n == null:
			continue
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		cell.add_child(_small(n.def.label))
		var bar := PixelBar.new()
		bar.segments = BAR_SEGMENTS
		cell.add_child(bar)
		_needs_grid.add_child(cell)
		_need_rows.append({"need": n, "bar": bar})

# ---------------- 刷新 ----------------

func _on_tick(_dt: float) -> void:
	if visible:
		_refresh()

## 任一生物死亡 —— 只在**死的是主角**时反应（按引用比对，不认 id/物种）。
func _on_creature_died(c: Node) -> void:
	if c != _player:
		return
	_dead_lbl.visible = true
	_dead_lbl.text = "── 你死了 ──"
	_refresh()

func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# 总血
	var body := _player.get_component(Body) as Body
	if body != null:
		var hp := body.total_hp()
		var mx := body.total_max()
		var r := hp / mx if mx > 0.0 else 0.0
		_total_bar.set_ratio(r)
		_total_lbl.text = "%d/%d" % [int(hp), int(mx)]

	# 体力：比例是**相对当前上限**的（所以"满"不代表能跑很久 —— 上限可能已经缩了），
	# 数字显示 `当前/上限`，缩了直接看得见。
	var sp := _player.get_component(Sprint) as Sprint
	if sp != null and _stamina_bar != null:
		_stamina_bar.set_ratio(sp.stamina_ratio())
		_stamina_lbl.text = "%d/%d" % [int(sp.stamina()), int(sp.stamina_max())]

	# 需求
	for row in _need_rows:
		var n: Need = row["need"]
		(row["bar"] as PixelBar).set_ratio(n.ratio())

	# 睡眠状态。清醒时整行隐藏（不占位、不打扰）。
	var sl := _player.get_component(Sleep) as Sleep
	if sl != null and _sleep_lbl != null:
		if sl.state() == Sleep.State.AWAKE:
			_sleep_lbl.visible = false
		else:
			_sleep_lbl.visible = true
			var spd := int(round(TimeSystem.speed))
			var tail := "　时间 ×%d" % spd if spd > 1 else ""
			_sleep_lbl.text = "%s%s" % [sl.state_text(), tail]

	# 阶段 / 性别（**不再重复"第 N 天"** —— 屏幕顶部时钟已在显示，问题4 的同一诉求）。
	var ag := _player.get_component(Aging) as Aging
	var lin := _player.get_component(Lineage) as Lineage
	if ag != null:
		var stage_names := ["幼年", "成年", "老年"]
		var sex := ""
		if lin != null:
			sex = " · %s" % lin.sex_text()
		_age_lbl.text = "[%s]%s" % [stage_names[ag.stage()], sex]

# ---------------- 小工具 ----------------

## 小字标签（11px）。**必须在控件自己身上设** —— 父控件的主题覆盖不会传给子节点。
func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	return l
