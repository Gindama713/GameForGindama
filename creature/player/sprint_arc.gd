class_name SprintArc
extends Node2D

## 角色身旁的**体力圈**（2026-09-21）—— 跑动 / 喘气时出现，回满后淡出。
##
## ══════════════════════════════════════════════════════════════════
## 一、它表示什么：**体力**（不是疲劳）
## ══════════════════════════════════════════════════════════════════
##   生物身上有**两条**条（见 `sprint.gd` 文件头）：
##     · **疲劳条** —— 慢，满槽 2 个游戏日，只有睡觉能回 → 在 **HUD** 里（和饥饿/口渴/保暖并排）
##     · **体力条** —— 快，满槽 100/15 ≈ 6.7 秒，停下就回 → **就是这个圈**
##
##   ⚠ **别在圈上再画"上限刻度"**（我 2026-09-21 试过，用户否掉了）：一个圈只表示一件事。
##     上限（= 疲劳值）在 HUD 那一行用 `当前/上限` 两个数表达，那里才放得下两个数。
##
## ══════════════════════════════════════════════════════════════════
## 二、圈长按**绝对刻度**画（不是"占当前上限的几成"）
## ══════════════════════════════════════════════════════════════════
##   圈长 = `体力 / 满值`，满值读 `NeedDef.max_value`（疲劳那条，当前 100）—— **不写死**。
##
##   【为什么不按"占当前上限的比例"】上限是动态的（= 疲劳值）。若按比例画，
##   **一个疲劳只剩 20 的角色，圈会画成满的** —— 而它其实只能跑 1.3 秒。
##   按绝对刻度画，疲劳低的角色圈**天然就短**，一眼就能看出"跑不久"。
##   底环（暗色的一整圈）就是那 100 的参照，短的那截一眼看得出来。
##
## ══════════════════════════════════════════════════════════════════
## 三、颜色：白 → 黄 → 红（用户拍板）
## ══════════════════════════════════════════════════════════════════
##   | 区间（占满值 100） | 颜色 | 读法 |
##   |---|---|---|
##   | `≥ 35%` | **白** | 正常，跑得动 |
##   | `[15%, 35%)` | **黄** | **跑不动下一程了**（35% 正是起跑线 `START_MIN_RATIO`）|
##   | `(0, 15%)` | **红** | 马上要见底 |
##   | `= 0` | **空**（只剩底环） | 跑不了了 |
##
##   判据是 **`<`**（严格小于）—— 所以"正好 35%"仍然是白、"正好 15%"仍然是黄。
##   边界本身是任意的，但**判据必须只写一处**（`color_for()`），别在别处再抄一遍。
##
##   33% 那条与 `Sprint.START_MIN_RATIO` 对齐不是巧合 —— 低于它就起步不了，
##   所以"变黄"与"你不能再起跑"是同一件事，玩家不需要记两套阈值。
##
##   ⚠ 不再有"力竭冷却"的独立颜色：力竭时体力就是 0，圈自然空了。
##     而 `Sprint.gauge_visible()` 里那条"有人想跑但跑不动"的余辉会保证**底环仍然显示**，
##     于是"按了 Shift 没反应"至少能看见一圈空的，而不是什么都没有。

## 圈的半径（像素）。**取 19 是为了让圈真的"包住"角色**（用户要求"圈大一点"）。
##
## 【为什么必须大于 16】一格 32px、精灵铺满一格 ⇒ 精灵的包围盒是 ±16。
##   半径 ≤16 的圈会**压在角色身上**（实测半径 13 / 15 都糊在头和肩膀上，看不出是个环）。
##   19 让圈落在精灵外沿 3px 处，才读得出"套在角色外面的一圈"。
##   ⚠ 代价：圈会伸进相邻格约 3px。它是纯表现层的覆盖物，不影响逻辑，可接受。
const RADIUS := 19.0
const WIDTH := 3.0
## 从正上方开始顺时针填充（Godot 的 y 轴向下，所以角度增大 = 顺时针）。
const START_ANGLE := -PI / 2.0
## 画弧的采样点数。半径 19 用 48 段已经看不出折线。
const SEGMENTS := 48

const FILL := Color(1.0, 1.0, 1.0, 1.0)              # 白：正常
const LOW := Color(1.0, 0.85, 0.15, 1.0)             # 黄：快没了
const CRIT := Color(0.95, 0.28, 0.22, 1.0)           # 红：马上见底
## 底环：**一整圈暗灰**，给出"满值"的参照，并让"体力为 0"仍然看得见一个空环。
##
## 【为什么不是纯黑】地面本来就是纯黑（`default_clear_color`）——
##   用 `Color(0,0,0,α)` 画的底环在黑色上**完全看不见**，
##   于是"体力跑空了"会变成屏幕上一片空白，玩家分不清"跑不动了"和"没这个功能"。
##   调成暗灰（0.28）之后：空圈是个能看见的浅灰环，填充叠在它上面。
## 【为什么比填充粗 +1.5】给白/黄/红描一圈边，让它们在亮色精灵/亮色草地上也读得出来。
const BACKDROP := Color(0.28, 0.28, 0.28, 0.7)
const BACKDROP_EXTRA := 1.5

## 低于它转黄。**直接引用 `Sprint.START_MIN_RATIO`，不抄字面量** ——
## 见文件头第三节：这两件事本来就是同一件事（低于起跑线 = 不能再起跑），
## 抄一份 0.35 就等着哪天 `START_MIN_RATIO` 被调了而这里没跟着变。
const LOW_RATIO := Sprint.START_MIN_RATIO
## 低于它转红。
const CRIT_RATIO := 0.15

## 淡入淡出的速度（每秒收敛掉的比例系数，指数平滑 → 与帧率无关）。
const FADE_SPEED := 9.0
## 低于此值就彻底不画（省掉一次 draw_arc）。
const MIN_ALPHA := 0.02

var _creature: Creature = null
var _sprint: Sprint = null
var _alpha := 0.0

func _ready() -> void:
	# 宿主就是父节点。取不到就停用（这个节点只该挂在 Creature 下面）。
	_creature = get_parent() as Creature
	if _creature == null:
		push_warning("[体力圈] 父节点不是 Creature，本节点不起作用")
		return
	# ⚠⚠ **不能在这里 `get_component()`** —— Godot 的 `_ready` 是**子节点先跑**，
	#   而组件是宿主在**它自己的 `_ready`** 里才装配的（`Creature._build_components()`）。
	#   所以此刻取组件**必然是 null** —— 圈会永远不显示（实测踩过：
	#   探针打印 `圆弧可见=true`，但截图上主角周围一圈全黑）。
	#   ⇒ 延后到本帧末（那时所有节点的 `_ready` 都跑完了）再取。
	_bind.call_deferred()

## 取组件引用。延后调用，见 `_ready()` 的说明。
func _bind() -> void:
	if _creature == null or not is_instance_valid(_creature):
		return
	_sprint = _creature.get_component(Sprint) as Sprint
	if _sprint == null:
		# 没挂 Sprint 的物种（将来的鱼/鸟）不该画这个圈。**静默停用**是对的 ——
		# 这不是配置错误，只是"这个物种没有疾跑"。
		set_process(false)
		return
	# 起始透明度按当前状态定，避免开局从 0 淡入一个"其实满体力"的圈。
	_alpha = 1.0 if _sprint.gauge_visible() else 0.0

## ⚠⚠ **重绘条件必须同时看"透明度"和"圈长"**（2026-09-21 修的 bug）。
##
## 【原来的写法错在哪】只判 `_alpha` 变没变：
##   ```
##   if is_equal_approx(_alpha, want): return     # ← 跑起来时 _alpha 恒为 1.0
##   ```
##   于是**跑起来之后 `_alpha` 稳定在 1.0，`_process` 每帧都从这里返回、从不 `queue_redraw()`**
##   ⇒ 圈**冻结在最初那一刻的长度**，跑再久也不动 —— 现象就是用户报的"体力条根本不减少"。
##   而截图验证时看不出来：每次截图前透明度都在变（淡入），恰好触发了一次重绘。
##   ⇒ **教训：`_process` 里的 early-return 必须把"这一帧要不要重画"的全部条件都算进去**，
##     只判其中一个（哪怕它看起来最活跃）就会漏掉另一种变化。
##
##   现在：透明度 **或** 圈长任一变化 → 重绘。
var _last_fill := -1.0

func _process(dt: float) -> void:
	if _sprint == null or _creature == null:
		return
	# 死了 / 藏进高草 -> 不画（藏起来就该彻底看不见，否则会暴露位置）
	if not _creature.is_alive() or _creature.is_concealed():
		if _alpha != 0.0:
			_alpha = 0.0
			queue_redraw()
		return
	var want := 1.0 if _sprint.gauge_visible() else 0.0
	var fill := _sprint.stamina_fill_ratio() if want > 0.0 else 0.0
	var alpha_moved := not is_equal_approx(_alpha, want)
	var fill_moved := not is_equal_approx(fill, _last_fill)
	if not alpha_moved and not fill_moved:
		return
	if alpha_moved:
		_alpha = lerpf(_alpha, want, 1.0 - exp(-FADE_SPEED * dt))
		if absf(_alpha - want) < MIN_ALPHA:
			_alpha = want
	_last_fill = fill
	queue_redraw()

func _draw() -> void:
	if _sprint == null or _alpha <= MIN_ALPHA:
		return
	# 底环：一整圈暗色。它同时干两件事 —— ① 给"还剩多少"当参照；
	#   ② 体力为 0 时让"空圈"看得见（否则"跑不动"会变成屏幕上什么都没有）。
	draw_arc(Vector2.ZERO, RADIUS, START_ANGLE, START_ANGLE + TAU, SEGMENTS,
		Color(BACKDROP.r, BACKDROP.g, BACKDROP.b, BACKDROP.a * _alpha), WIDTH + BACKDROP_EXTRA, false)
	# 体力圈：**绝对刻度**（占满值 100 的比例），见文件头第二节。
	var fill := _sprint.stamina_fill_ratio()
	if fill <= 0.0:
		return                       # 空了就只剩底环 —— 这就是"没了就空了"
	var col := color_for(fill)
	draw_arc(Vector2.ZERO, RADIUS, START_ANGLE, START_ANGLE + TAU * fill, SEGMENTS,
		Color(col.r, col.g, col.b, _alpha), WIDTH, false)

## 按圈长（占满值 100 的比例）选颜色。见文件头第三节。
## 抽成静态函数是为了让探针能直接断言颜色，不必去截图比对像素。
static func color_for(fill: float) -> Color:
	if fill < CRIT_RATIO:
		return CRIT
	if fill < LOW_RATIO:
		return LOW
	return FILL
