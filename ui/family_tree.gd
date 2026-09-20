class_name FamilyTree
extends Control
## 族谱树面板（自绘 Control）—— **实时**反映当前世界状态：
##   - 头像大小 = 该猪**当前** `Aging.size_ratio()`（孩子多大画多大，会随时间长大）；
##   - **死掉的猪也画**（灰 + "已故"，不消失），数据来自 FamilyRegistry 的已故快照；
##   - **没有的亲属不画空槽**（只画真实存在过的节点）；
##   - 连线用标准系谱画法（夫妻横线→中点下垂→子女横线→各垂线），只连真实存在的；
##   - **纯黑白**（贴合项目像素黑白主题）：活体白框、已故灰框，无性别彩色；
##   - **点节点不再换中心/变格式**（用户要求）；只有关闭按钮交互。
##
## 【只读】Lineage / FamilyRegistry / Aging；不持业务状态。

const PIG_TEX: Texture2D = preload("res://creature/pig/art/pig.png")
const NODE := 56.0
const GAP := 22.0
const ROW_H := 108.0
const PAD := 24.0
const CANVAS_W := 620.0

const COL_LINE := Color(0.85, 0.85, 0.85)
const COL_ALIVE := Color(1.0, 1.0, 1.0)
const COL_DEAD := Color(0.45, 0.45, 0.45)
const COL_TEXT := Color(0.9, 0.9, 0.9)

var focus: Creature = null
var _nodes: Array = []     # {rect, label, alive, size, creature-or-null}
var _edges: Array = []     # [Vector2, Vector2]
var _close_rect := Rect2()
var _zoom: float = 1.0          # 族谱内容缩放（滚轮）
var _pan: Vector2 = Vector2.ZERO  # 族谱内容平移（左键拖动）
var _dragging := false
var _drag_start := Vector2.ZERO
var _pan_start := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	TimeSystem.tick.connect(_on_tick)

## 打开时重建（反映"此刻"的世界）；打开期间每 tick 刷新活体大小（实时长大）。
func open(c: Creature) -> void:
	focus = c
	_zoom = 1.0
	_pan = Vector2.ZERO
	_layout()
	visible = true
	queue_redraw()

func close() -> void:
	visible = false
	focus = null

func _on_tick(_dt: float) -> void:
	if not visible:
		return
	# 实时：活体节点尺寸随成长更新
	var changed := false
	for n in _nodes:
		if n["alive"] and n["creature"] != null:
			var ag: Aging = (n["creature"] as Creature).get_component(Aging) as Aging
			var s := ag.size_ratio() if ag != null else 1.0
			if not is_equal_approx(s, n["size"]):
				n["size"] = s
				changed = true
	if changed:
		queue_redraw()

## 族谱内交互：滚轮=以鼠标为中心缩放；左键拖背景=平移；关闭按钮=关；点节点不变格式。
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _close_rect.has_point(mb.position):
					close()
				else:
					_dragging = true          # 拖背景平移
					_drag_start = mb.position
					_pan_start = _pan
			else:
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan = _pan_start + (event.position - _drag_start)
		queue_redraw()
		accept_event()

## 以鼠标位置 m 为中心缩放 f 倍（保持 m 下的内容点不动）。
func _zoom_at(m: Vector2, f: float) -> void:
	var c := (m - _pan) / _zoom
	_zoom = clampf(_zoom * f, 0.4, 3.0)
	_pan = m - c * _zoom
	queue_redraw()

# ---------------- 解析（活体 or 已故快照） ----------------

func _resolve(id: int) -> Dictionary:
	if id < 0 or not FamilyRegistry.knows(id):
		return {}
	var c := FamilyRegistry.get_creature(id)
	if c != null:
		var lin: Lineage = c.get_component(Lineage) as Lineage
		var ag: Aging = c.get_component(Aging) as Aging
		var alive := c.is_alive()      # 在册≠活着：尸体节点不释放，须按 is_alive 判
		return {
			"id": id, "alive": alive, "creature": (c if alive else null),
			"sex": (lin.sex if lin != null else Lineage.Sex.MALE),
			"size": (ag.size_ratio() if (ag != null and alive) else 1.0),
			"mother_id": (lin.mother_id if lin != null else -1),
			"father_id": (lin.father_id if lin != null else -1),
			"children_ids": (lin.children_ids if lin != null else []),
			# **头像与配色跟着物种走**（2026-09-20 修）：此前不带这两个字段，
			# `_draw()` 一律画 PIG_TEX → 主角（人）在族谱里"还是一头猪"。
			# ⚠ `c.def` 是 Variant（Creature.def 是导出成员）→ 显式标类型（§2.4 坑 7）。
			"texture": _tex_of(c),
			"color": _color_of(c),
		}
	var rec := FamilyRegistry.get_record(id)
	if rec.is_empty():
		return {}
	return {
		"id": id, "alive": false, "creature": null,
		"sex": rec["sex"], "size": 1.0,
		"mother_id": rec["mother_id"], "father_id": rec["father_id"],
		"children_ids": rec["children_ids"],
		# 已故者用出生时留在 FamilyRegistry 的那份快照（见 unregister()）——
		# 没有它，已故主角也会被画成猪。缺失时回退到猪图（旧行为，至少不崩）。
		"texture": (rec.get("texture") if rec.get("texture") != null else PIG_TEX),
		"color": rec.get("color", COL_TEXT),
	}

## 活体的贴图：`def.texture` 优先；没配图（纯逻辑生物）→ null，由 `_draw` 回退到色块/猪图。
func _tex_of(c: Creature) -> Texture2D:
	var d: CreatureDef = c.def
	return d.texture if d != null else null

## 活体的配色（`def.map_color`）。
func _color_of(c: Creature) -> Color:
	var d: CreatureDef = c.def
	return d.map_color if d != null else COL_TEXT

# ---------------- 布局 ----------------

func _layout() -> void:
	_nodes.clear()
	_edges.clear()
	if focus == null:
		return
	var self_n := _resolve(focus.id)
	if self_n.is_empty():
		return
	var mother := _resolve(self_n["mother_id"])
	var father := _resolve(self_n["father_id"])
	# 配偶 = 任一子女的另一位亲代（活或故）
	var spouse: Dictionary = {}
	for cid in self_n["children_ids"]:
		var kid := _resolve(cid)
		if kid.is_empty():
			continue
		var other_id: int = kid["mother_id"] if self_n["sex"] == Lineage.Sex.MALE else kid["father_id"]
		spouse = _resolve(other_id)
		if not spouse.is_empty():
			break
	# 祖辈（仅当对应父/母存在）
	var gm_m: Dictionary = {}; var gf_m: Dictionary = {}
	var gm_f: Dictionary = {}; var gf_f: Dictionary = {}
	if not mother.is_empty():
		gm_m = _resolve(mother["mother_id"]); gf_m = _resolve(mother["father_id"])
	if not father.is_empty():
		gm_f = _resolve(father["mother_id"]); gf_f = _resolve(father["father_id"])
	var kids: Array = []
	for cid in self_n["children_ids"]:
		var k := _resolve(cid)
		if not k.is_empty():
			kids.append(k)

	var cx := CANVAS_W * 0.5
	var y_gg := PAD
	var y_p := PAD + ROW_H
	var y_s := PAD + ROW_H * 2
	var y_k := PAD + ROW_H * 3

	# 父母行（**先放**：祖辈要以父/母的位置为基准，否则 _cx_of 读到没 rect 的字典会崩）
	if not mother.is_empty() and not father.is_empty():
		_place_pair(mother, father, cx, y_p, ["母亲", "父亲"])
	elif not mother.is_empty():
		_place_single(mother, cx, y_p, "母亲")
	elif not father.is_empty():
		_place_single(father, cx, y_p, "父亲")
	# 祖辈行（居中于各自子女=父/母 之上；**只画真实存在的**，不画空槽）
	if not mother.is_empty():
		_place_grandparents(gm_m, gf_m, _cx_of(mother), y_gg, ["外公", "外婆"])
	if not father.is_empty():
		_place_grandparents(gm_f, gf_f, _cx_of(father), y_gg, ["爷爷", "奶奶"])
	# 自己 + 配偶
	if not spouse.is_empty():
		_place_pair(self_n, spouse, cx, y_s, ["自己", "配偶"])
	else:
		_place_single(self_n, cx, y_s, "自己")
	# 子女行（居中铺开）
	_place_children(kids, cx, y_k)

	# ---- 连线（只连真实存在的）----
	if not mother.is_empty() and not father.is_empty():
		_couple_drop(mother, father, _top_of(self_n))
	elif not mother.is_empty():
		_edges.append([_bottom_of(mother), _top_of(self_n)])
	elif not father.is_empty():
		_edges.append([_bottom_of(father), _top_of(self_n)])
	if not mother.is_empty():
		if not gm_m.is_empty() and not gf_m.is_empty():
			_couple_drop(gm_m, gf_m, _top_of(mother))
		elif not gm_m.is_empty():
			_edges.append([_bottom_of(gm_m), _top_of(mother)])
		elif not gf_m.is_empty():
			_edges.append([_bottom_of(gf_m), _top_of(mother)])
	if not father.is_empty():
		if not gm_f.is_empty() and not gf_f.is_empty():
			_couple_drop(gm_f, gf_f, _top_of(father))
		elif not gm_f.is_empty():
			_edges.append([_bottom_of(gm_f), _top_of(father)])
		elif not gf_f.is_empty():
			_edges.append([_bottom_of(gf_f), _top_of(father)])
	# 自己(+配偶) → 子女
	if not kids.is_empty():
		var anchor := _bottom_of(self_n)
		if not spouse.is_empty():
			anchor = Vector2(cx, self_n["rect"].position.y + NODE * 0.5)
			_edges.append([_right_of(self_n), _left_of(spouse)])   # 夫妻横线
		if kids.size() == 1:
			_edges.append([anchor, _top_of(kids[0])])
		else:
			var bar_y := y_s + NODE + 26.0
			_edges.append([anchor, Vector2(cx, bar_y)])
			var x0: float = kids[0]["rect"].position.x + NODE * 0.5
			var x1: float = kids[kids.size() - 1]["rect"].position.x + NODE * 0.5
			_edges.append([Vector2(x0, bar_y), Vector2(x1, bar_y)])
			for k in kids:
				_edges.append([Vector2(k["rect"].position.x + NODE * 0.5, bar_y), _top_of(k)])

	size = Vector2(CANVAS_W, y_k + NODE + PAD + 20)
	custom_minimum_size = size

func _cx_of(n: Dictionary) -> float:
	return n["rect"].position.x + NODE * 0.5

func _top_of(n: Dictionary) -> Vector2:
	return Vector2(_cx_of(n), n["rect"].position.y)

func _bottom_of(n: Dictionary) -> Vector2:
	return Vector2(_cx_of(n), n["rect"].end.y)

func _left_of(n: Dictionary) -> Vector2:
	return Vector2(n["rect"].position.x, n["rect"].position.y + NODE * 0.5)

func _right_of(n: Dictionary) -> Vector2:
	return Vector2(n["rect"].end.x, n["rect"].position.y + NODE * 0.5)

## 夫妻横线 + 中点下垂到 target（标准系谱）。
func _couple_drop(a: Dictionary, b: Dictionary, target: Vector2) -> void:
	_edges.append([_right_of(a), _left_of(b)])
	var mx := (_cx_of(a) + _cx_of(b)) * 0.5
	var my: float = a["rect"].position.y + NODE * 0.5
	_edges.append([Vector2(mx, my), target])

func _add_node(n: Dictionary, x: float, y: float, label: String) -> void:
	n["rect"] = Rect2(Vector2(x, y), Vector2(NODE, NODE))
	n["label"] = label + ("" if n["alive"] else "·已故")
	_nodes.append(n)

func _place_single(n: Dictionary, cx: float, y: float, label: String) -> void:
	_add_node(n, cx - NODE * 0.5, y, label)

func _place_pair(a: Dictionary, b: Dictionary, cx: float, y: float, labels: Array) -> void:
	_add_node(a, cx - GAP * 0.5 - NODE, y, labels[0])
	_add_node(b, cx + GAP * 0.5, y, labels[1])

## 祖辈：只画真实存在的（两个=一对居中；只有一个=单独居中），**不画空槽**。
func _place_grandparents(a: Dictionary, b: Dictionary, cx: float, y: float, labels: Array) -> void:
	if not a.is_empty() and not b.is_empty():
		_place_pair(a, b, cx, y, labels)
	elif not a.is_empty():
		_place_single(a, cx, y, labels[0])
	elif not b.is_empty():
		_place_single(b, cx, y, labels[1])

func _place_children(kids: Array, cx: float, y: float) -> void:
	var n := kids.size()
	if n == 0:
		return
	var total := n * NODE + (n - 1) * GAP
	var x := cx - total * 0.5
	for i in n:
		var lbl := "儿子" if kids[i]["sex"] == Lineage.Sex.MALE else "女儿"
		_add_node(kids[i], x, y, lbl)
		x += NODE + GAP

# ---------------- 绘制（纯黑白） ----------------

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.08, 0.94))
	_close_rect = Rect2(Vector2(size.x - 34, 6), Vector2(28, 28))
	draw_rect(_close_rect, Color(0.2, 0.2, 0.22))
	draw_string(ThemeDB.fallback_font, _close_rect.position + Vector2(8, 20), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_TEXT)
	draw_string(ThemeDB.fallback_font, Vector2(PAD, 20), "族谱（实时·滚轮缩放/拖动平移）", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TEXT)
	# 内容（连线+节点）套用 pan/zoom 变换；背景/关闭/标题保持屏幕空间
	draw_set_transform(_pan, 0.0, Vector2(_zoom, _zoom))
	for e in _edges:
		draw_line(e[0], e[1], COL_LINE, 2.0)
	for n in _nodes:
		var r: Rect2 = n["rect"]
		var border: Color = COL_ALIVE if n["alive"] else COL_DEAD
		draw_rect(r, border, false, 2.0)
		# 头像：活体按当前 size 缩放（实时长大）；已故灰色满格
		var s: float = n["size"] if n["alive"] else 1.0
		var aw := NODE * 0.86 * clampf(s, 0.2, 1.0)
		var ar := Rect2(r.position + (Vector2(NODE, NODE) - Vector2(aw, aw)) * 0.5, Vector2(aw, aw))
		var tint: Color = COL_TEXT if n["alive"] else COL_DEAD
		# **按节点自己的物种贴图**（2026-09-20 修）—— 此前这里硬编码 PIG_TEX，
		# 于是主角（人）在族谱里被画成猪。取不到图（纯逻辑生物）才回退到猪图。
		# ⚠ Dictionary 取出的是 Variant → 显式标类型（§2.4 坑 7）。
		var tex: Texture2D = n.get("texture")
		if tex == null:
			tex = PIG_TEX
		draw_texture_rect(tex, ar, false, tint)
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x - 8, r.end.y + 16), n["label"], HORIZONTAL_ALIGNMENT_LEFT, NODE + 16, 12, COL_TEXT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
