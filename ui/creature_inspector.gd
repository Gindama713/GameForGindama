extends PanelContainer

## 生物检视悬浮窗（调试 / 也可当游戏内 HUD）。
##  - 点生物 -> EventBus.creature_clicked -> 显示：名称/坐标/总血/部位/需求/性格(6维)+状态
##  - 生物死亡 -> EventBus.creature_died -> 切换成**尸体视图**
##  - 独立小窗、可拖动（按住标题栏拖）
##  - **紧凑网格布局**：部位 3 列 × 2 行、需求 4 列 × 1 行（原来竖着堆 10 行，又窄又高）
##  - 像素风：文字走全局像素字体（灰白），血量/需求用 PixelBar 小方块（不用进度条）
##  - 数据全部来自组件（Body / Needs）→ 换任何物种都能显示
##
## 【纪律】UI 自己知道它要显示哪两个组件（Body/Needs），**基类不需要认识它们**。
## 所以这里用 get_component(Body)，而不是 Creature 上开一个 get_body() 便利方法。

const PARTS_COLS := 3          # 部位：3 列 × 2 行
const NEEDS_COLS := 4          # 需求：4 列 × 1 行
const CELL_BAR_SEGMENTS := 6   # 格子里的像素条段数（短一点，格子才排得下 3 列）
## 本面板字号：全局主题 22，一行就要 30~38px，面板自然又窄又高。
## 实测（Godot 4.7）：**父控件上的 add_theme_*_override 不会向下继承**，子控件仍读到 22，
## 所以只能逐个控件设——见 _small_label()。
## 像素字体是 11px 原生 + antialiasing=0（字体 import 里关掉了），只有 11/22/33 这类整数倍才不糊。
const CELL_FONT_SIZE := 11     # 格子内容用原生尺寸：信息密集区，小一号才排得下

## 大脑驱动名 → 中文（状态行显示）
const DRIVE_LABEL := {
	"wander": "游荡", "social": "合群", "separate": "独行",
	"rest": "休息", "blocked": "被围", "idle": "发呆",
	"feed": "觅食", "cling": "跟妈",
}

var _creature: Creature
var _title_bar: HBoxContainer
var _name_lbl: Label
var _coord_lbl: Label
var _total_bar: PixelBar
var _total_lbl: Label
var _hp_row: HBoxContainer
var _total_section: VBoxContainer      # 活体专属：总血
var _needs_section: VBoxContainer      # 活体专属：需求
var _dead_lbl: Label
var _parts_grid: GridContainer
var _needs_grid: GridContainer
var _personality_grid: GridContainer
var _personality_section: VBoxContainer
var _state_lbl: Label
var _part_rows: Array = []   # {part, bar, status}
var _need_rows: Array = []   # {need, bar}
var _trait_rows: Array = []  # {id, bar, value}

var _dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pos := Vector2.ZERO
var _tree: FamilyTree = null

func _ready() -> void:
	_build()
	EventBus.creature_clicked.connect(_on_clicked)
	EventBus.creature_died.connect(_on_creature_died)
	EventBus.creature_removed.connect(_on_removed)   # 清屏移除 → 关面板（不再靠 is_instance_valid 兜底）
	TimeSystem.tick.connect(_on_tick)
	position = Vector2(32, 104)   # 初始位置（左侧；可拖动）
	# 族谱树**懒创建**（点「族谱」时才 new+add_child）：_ready 里 add_child 会因
	# "Parent node is busy setting up children" 失败，故不在这里建。
	hide()

func _build() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)

	# 标题栏（拖动区）
	_title_bar = HBoxContainer.new()
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_gui_input)
	vb.add_child(_title_bar)
	var title := Label.new(); title.text = "生物检视"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_bar.add_child(title)
	var close := Button.new(); close.text = "关闭"; close.pressed.connect(_on_close)
	_title_bar.add_child(close)

	# 名称 + 坐标合并一行（省一行高度）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	_name_lbl = Label.new(); head.add_child(_name_lbl)
	_coord_lbl = Label.new(); head.add_child(_coord_lbl)

	_dead_lbl = Label.new(); _dead_lbl.visible = false
	vb.add_child(_dead_lbl)

	# 总血（活体专属，尸体视图整块隐藏）
	_total_section = VBoxContainer.new()
	vb.add_child(_total_section)
	_hp_row = HBoxContainer.new(); _hp_row.add_theme_constant_override("separation", 8); _total_section.add_child(_hp_row)
	var hp_t := Label.new(); hp_t.text = "总血"; _hp_row.add_child(hp_t)
	_total_bar = PixelBar.new(); _total_bar.segments = 12; _hp_row.add_child(_total_bar)
	_total_lbl = Label.new(); _hp_row.add_child(_total_lbl)

	# 部位：网格 3 列 × 2 行（小标题与网格同一行，省一行高度）
	_parts_grid = GridContainer.new()
	_parts_grid.name = "PartsGrid"          # 便于调试定位
	_parts_grid.columns = PARTS_COLS
	_parts_grid.add_theme_constant_override("h_separation", 8)
	_parts_grid.add_theme_constant_override("v_separation", 3)
	vb.add_child(_caption_row("部位", _parts_grid))

	# 需求：网格 4 列 × 1 行
	_needs_section = VBoxContainer.new()
	vb.add_child(_needs_section)
	_needs_grid = GridContainer.new()
	_needs_grid.name = "NeedsGrid"          # 便于调试定位
	_needs_grid.columns = NEEDS_COLS
	_needs_grid.add_theme_constant_override("h_separation", 8)
	_needs_grid.add_theme_constant_override("v_separation", 3)
	_needs_section.add_child(_caption_row("需求", _needs_grid))

	# 性格：网格 3 列 × 2 行（6 维）+ 一行状态（当前驱动 / 合群度）
	_personality_section = VBoxContainer.new()
	vb.add_child(_personality_section)
	_personality_grid = GridContainer.new()
	_personality_grid.name = "PersonalityGrid"   # 便于调试定位
	_personality_grid.columns = 3
	_personality_grid.add_theme_constant_override("h_separation", 8)
	_personality_grid.add_theme_constant_override("v_separation", 3)
	_personality_section.add_child(_caption_row("性格", _personality_grid))
	_state_lbl = _small_label("")
	_personality_section.add_child(_state_lbl)

	var wound := Button.new(); wound.text = "调试：随机致伤"; wound.pressed.connect(_on_random_wound)
	vb.add_child(wound)

	# 家族：只留一个「族谱」按钮（用户要求删掉父/母/配偶，族谱树里本来就能看全）
	var fam := HBoxContainer.new(); fam.add_theme_constant_override("separation", 6)
	vb.add_child(fam)
	var b_tree := Button.new(); b_tree.text = "族谱"; b_tree.pressed.connect(_on_open_tree); fam.add_child(b_tree)

## 小标题 + 网格横向并排（原来标题独占一行，白白多两行高度）
func _caption_row(title_text: String, grid: GridContainer) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = title_text
	t.custom_minimum_size.x = 30
	h.add_child(t)
	h.add_child(grid)
	return h

## 小字标签（11px）。**必须在控件自己身上设**：父节点的主题覆盖不会传给子节点。
func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", CELL_FONT_SIZE)
	return l

## 一个紧凑格子：上排名字，下排像素条（可选：右侧状态文字）
func _make_cell(name_text: String, with_status: bool) -> Dictionary:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 1)
	cell.add_child(_small_label(name_text))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4); cell.add_child(row)
	var bar := PixelBar.new(); bar.segments = CELL_BAR_SEGMENTS; row.add_child(bar)
	var st: Label = null
	if with_status:
		st = _small_label(""); row.add_child(st)
	return {"root": cell, "bar": bar, "status": st}

# ---------------- 拖动窗口 ----------------
func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_start_mouse = event.global_position
		_drag_start_pos = position
	elif event is InputEventMouseMotion and _dragging:
		var new_pos: Vector2 = _drag_start_pos + (event.global_position - _drag_start_mouse)
		var vp := get_viewport_rect().size
		# 允许拖出一点，但标题栏永远留在屏幕内（面板不会拖丢找不回来）
		new_pos.x = clampf(new_pos.x, -size.x + 60.0, vp.x - 60.0)
		new_pos.y = clampf(new_pos.y, 0.0, vp.y - 40.0)
		position = new_pos

# ---------------- 选取 ----------------
func _on_clicked(c: Creature) -> void:
	_creature = c
	_rebuild()
	show()

## 选中的生物死了 → 重建一次，切成尸体视图。
## （视图形态由「唯一事实」is_alive() 决定，不靠每帧乱切 visible。）
func _on_creature_died(c: Node) -> void:
	if c == _creature:
		_rebuild()

## 选中的生物被移除（清屏等非死亡移除）→ 关面板、放掉引用。
func _on_removed(c: Node) -> void:
	if c == _creature:
		_on_close()

func _rebuild() -> void:
	if _creature == null:
		return
	_name_lbl.text = "%s" % (_creature.def.display_name if _creature.def != null else "?")

	# 部位格子（活体/尸体都要显示：死后数值本来就冻结了，正好当验尸）
	for child in _parts_grid.get_children():
		child.queue_free()
	_part_rows.clear()
	var body := _creature.get_component(Body) as Body
	if body != null:
		for part in body.parts:
			var c := _make_cell(part.def.label, true)
			_parts_grid.add_child(c["root"])
			_part_rows.append({"part": part, "bar": c["bar"], "status": c["status"]})
	else:
		var none := Label.new(); none.text = "（无部位数据）"; _parts_grid.add_child(none)

	# 需求格子
	for child in _needs_grid.get_children():
		child.queue_free()
	_need_rows.clear()
	var needs := _creature.get_component(Needs) as Needs
	if needs != null:
		for n in needs.needs:
			var c := _make_cell(n.def.label, false)
			_needs_grid.add_child(c["root"])
			_need_rows.append({"need": n, "bar": c["bar"]})
	else:
		var none := Label.new(); none.text = "（无需求数据）"; _needs_grid.add_child(none)

	# 性格格子（6 维：单字标签 + 像素条 + 数值）
	for child in _personality_grid.get_children():
		child.queue_free()
	_trait_rows.clear()
	var person := _creature.get_component(Personality) as Personality
	if person != null:
		for tid in Personality.IDS:
			var c := _make_cell(Personality.SHORT[tid], true)
			_personality_grid.add_child(c["root"])
			_trait_rows.append({"id": tid, "bar": c["bar"], "value": c["status"]})
	else:
		var none2 := Label.new(); none2.text = "（无性格数据）"; _personality_grid.add_child(none2)

	_apply_form()
	_refresh()

## 由唯一事实 is_alive() 决定：活体形态 / 尸体形态。**真正地隐藏**，不是嘴上说说。
func _apply_form() -> void:
	if _creature == null:
		return
	var alive := _creature.is_alive()
	_dead_lbl.visible = not alive
	_total_section.visible = alive
	_needs_section.visible = alive
	_state_lbl.visible = alive          # 性格 6 维死后保留（稳定特征），只有"当前状态"没意义
	if not alive:
		var why := _creature.lethal_reason_text()
		_dead_lbl.text = "── 已死亡 · 模拟已停止 ──" if why.is_empty() else "── 已死亡（%s）· 模拟已停止 ──" % why

func _on_tick(_dt: float) -> void:
	if visible and _creature != null:
		_refresh()

func _refresh() -> void:
	if _creature == null or not is_instance_valid(_creature):
		_on_close()
		return
	_coord_lbl.text = "(%d, %d)" % [_creature.coord.x, _creature.coord.y]

	var body := _creature.get_component(Body) as Body
	if body != null:
		for r in _part_rows:
			var part: BodyPart = r["part"]
			r["bar"].set_ratio(part.ratio())
			r["status"].text = part.status_text()

	# 死亡可能在两次点击之间发生，这里兜一次，保证形态永远跟得上事实
	if not _creature.is_alive():
		if _total_section.visible or _needs_section.visible or not _dead_lbl.visible:
			_apply_form()
		return

	if body != null:
		var hp := body.total_hp()
		var mx := body.total_max()
		_total_bar.set_ratio(hp / mx if mx > 0.0 else 0.0)
		_total_lbl.text = "%d/%d" % [int(hp), int(mx)]
	var needs := _creature.get_component(Needs) as Needs
	if needs != null:
		for r in _need_rows:
			var n: Need = r["need"]
			r["bar"].set_ratio(n.ratio())

	# 性格：6 维数值 + 状态行（当前驱动 / 合群度）
	var person := _creature.get_component(Personality) as Personality
	if person != null:
		for r in _trait_rows:
			var v := person.get_trait(r["id"])
			r["bar"].set_ratio(v)
			r["value"].text = "%.2f" % v
	var brain := _creature.get_component(Brain) as Brain
	var drive: String = brain.last_drive if brain != null else "-"
	var soc: float = person.sociability() if person != null else 0.5
	_state_lbl.text = "状态 %s · 合群 %.2f" % [DRIVE_LABEL.get(drive, drive), soc]

func _on_random_wound() -> void:
	if _creature == null:
		return
	var body := _creature.get_component(Body) as Body
	if body != null:
		body.random_wound()   # 日志由 Body 自己打（"受伤" 分类），UI 不重复
	_refresh()

func _on_close() -> void:
	hide()
	_creature = null

# ---------------- 族谱树入口（唯一按钮） ----------------
func _on_open_tree() -> void:
	if _creature == null or not is_instance_valid(_creature):
		Log.ev("调试", "族谱：请先点选一只猪")
		return
	if _tree == null:
		_tree = FamilyTree.new()
		if get_parent() != null:
			get_parent().add_child(_tree)
	# 居中显示 + 置顶，保证一定看得见
	var vp := get_viewport()
	if vp != null:
		var vs := vp.get_visible_rect().size
		_tree.position = Vector2(maxf((vs.x - 560) * 0.5, 8), maxf((vs.y - 480) * 0.5, 8))
	_tree.open(_creature)
