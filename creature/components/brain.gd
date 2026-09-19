class_name Brain
extends CreatureComponent

## 融合式大脑 —— 多个「行为驱动」各出一份 (方向, 权重)，加权融合后挑最贴近的可走方向。
## 取代原来的 WanderBrain（无条件游荡 → 猪永远在走，没有停的时候）。
##
## 驱动（权重全是占位值，跑出来再调）：
##   Wander   游荡   永远在，权重随「活力」上升
##   Social   合群   附近有同类时，权重 = 合群度
##   Separate 独处   附近有同类时，权重 = 1−合群度
##   Rest     休息   权重 = (1−活力)+(1−疲劳)+夜晚加权；压过其余驱动 → **真的停下不动**（并睡回疲劳）
##
## 【纪律】只通过协议与别人对话：
##   要可走方向 → GridMover（不认识它的内部）；要脾气 → Personality；要邻居 → Perception。
##   缺 Personality / Perception 也能跑（退化为中性游荡），不静默崩、不静默误判。

## 驱动权重（占位）
const WANDER_BASE := 0.35
const WANDER_ENERGY := 0.5
const SOCIAL_WEIGHT := 1.0
const SEPARATE_WEIGHT := 1.0
const REST_WEIGHT := 1.2
const FATIGUE_REST_WEIGHT := 0.8   # 疲劳→休息意愿（减速而非致命，见 need_def.gd 注释）
const FATIGUE_SLOW_FACTOR := 1.5   # 疲劳→决策间隔放大（越累动得越稀）
const NIGHT_REST_BONUS := 0.7      # 夜晚→休息加权（大部分猪夜里歇着；够大又不至于全歇）
const SLEEP_RECOVER_RATE := 0.2    # 休息/睡觉时疲劳回复速率（每分钟；10 小时夜≈回满）

var _timer: float = 0.0
var last_drive: String = "wander"   # 上一次决策选中了什么（调试/检视面板用）

func requires() -> Array:
	return [GridMover]              # 硬依赖：没有移动组件就无从行动

func setup(host: Node) -> void:
	super.setup(host)
	last_drive = "wander"
	_reset_timer()

func tick(dt: float) -> void:
	# 不判断生死 —— 死了就不会被 tick（Creature.die() 已把宿主摘出时钟）
	_timer -= dt
	if _timer <= 0.0:
		_decide_and_act()
		_reset_timer()
	_recover_while_resting(dt)      # 处在「休息」时睡觉回疲劳

# ---------------- 决策 ----------------

func _decide_and_act() -> void:
	var mover := creature.get_component(GridMover) as GridMover
	if mover == null:
		return
	var dirs := mover.free_directions()
	if dirs.is_empty():
		last_drive = "blocked"
		return

	# 脾气（缺则中性）
	var energy := 0.5
	var sociability := 0.5
	var person := creature.get_component(Personality) as Personality
	if person != null:
		energy = person.get_trait("energy")
		sociability = person.sociability()

	# 疲劳：累了更想歇、更不想动（减速而非死亡，见 need_def.gd 注释）
	var fatigue_ratio := _fatigue_ratio()

	# --- Rest 休息：低活力 / 高疲劳都想歇；夜里再额外加权 → 大部分猪夜里歇着 ---
	var rest_w := (1.0 - energy) * REST_WEIGHT + (1.0 - fatigue_ratio) * FATIGUE_REST_WEIGHT
	if TimeSystem.is_night():
		rest_w += NIGHT_REST_BONUS

	# --- Wander 游荡：随机方向，权重随活力 ---
	var wander_dir := Vector2(GridMover.DIRS[creature.rng.randi_range(0, GridMover.DIRS.size() - 1)])
	var wander_w := WANDER_BASE + energy * WANDER_ENERGY

	# --- Social / Separate：要有同类邻居才起作用 ---
	var social_w := 0.0
	var separate_w := 0.0
	var social_dir := Vector2.ZERO
	var separate_dir := Vector2.ZERO
	var perc := creature.get_component(Perception) as Perception
	if perc != null:
		var ns := perc.neighbors()
		if not ns.is_empty():
			social_w = sociability * SOCIAL_WEIGHT
			separate_w = (1.0 - sociability) * SEPARATE_WEIGHT
			social_dir = _dir_to_centroid(ns)
			separate_dir = _dir_from_nearest(ns)

	# 休息压过一切 → 不动（这就是「不再一直走」的机制）
	if rest_w > 0.0 and rest_w >= maxf(maxf(wander_w, social_w), separate_w):
		last_drive = "rest"
		return

	var desired := wander_dir * wander_w + social_dir * social_w + separate_dir * separate_w
	if desired.length_squared() < 0.0001:
		last_drive = "idle"
		return
	var best := _pick_best(desired, dirs)
	if mover.try_step(best):
		last_drive = _dominant(wander_w, social_w, separate_w)

## 取与 desired 夹角最小的可走方向（可走方向都是单位轴向量，比点积即可）。
func _pick_best(desired: Vector2, dirs: Array[Vector2i]) -> Vector2i:
	var dn := desired.normalized()
	var best: Vector2i = dirs[0]
	var best_dot := -INF
	for d in dirs:
		var dot := dn.dot(Vector2(d))
		if dot > best_dot:
			best_dot = dot
			best = d
	return best

## 朝邻居重心的单位向量（凝聚）。
func _dir_to_centroid(ns: Array) -> Vector2:
	var sum := Vector2.ZERO
	for o in ns:
		sum += Vector2((o as Creature).coord - creature.coord)
	if sum.length_squared() < 0.0001:
		return Vector2.ZERO
	return sum.normalized()

## 背离最近邻居的单位向量（分离）。
func _dir_from_nearest(ns: Array) -> Vector2:
	var nearest: Creature = null
	var best_d := INF
	for o in ns:
		var c := o as Creature
		var d := Vector2(c.coord - creature.coord).length_squared()
		if d < best_d:
			best_d = d
			nearest = c
	if nearest == null:
		return Vector2.ZERO
	var away := Vector2(creature.coord - nearest.coord)
	if away.length_squared() < 0.0001:
		return Vector2.ZERO
	return away.normalized()

func _dominant(wander_w: float, social_w: float, separate_w: float) -> String:
	var m := maxf(maxf(wander_w, social_w), separate_w)
	if m == wander_w:
		return "wander"
	if m == social_w:
		return "social"
	return "separate"

## 决策间隔：基数来自物种（CreatureDef.move_interval），随活力缩短；休息后拉长。
func _reset_timer() -> void:
	var base := 1.0
	if creature.def != null and creature.def.move_interval > 0.0:
		base = creature.def.move_interval
	var energy := 0.5
	var person := creature.get_component(Personality) as Personality
	if person != null:
		energy = person.get_trait("energy")
	var mult := 1.6 - energy              # 高活力 → 更频繁
	if last_drive == "rest":
		mult *= 2.5                       # 休息要歇久一点
	var fr := _fatigue_ratio()
	if fr < 1.0:
		mult *= 1.0 + (1.0 - fr) * FATIGUE_SLOW_FACTOR   # 越累决策越稀 → 网格上减速
	var t: float = base * mult + creature.rng.randf_range(-0.2, 0.2)
	_timer = maxf(t, 0.1)

## 调试自述（生成日志 + 调试器检查器里的 debug/components/brain 行）
func debug_state() -> String:
	return "上次=%s 下次 %.1fs" % [last_drive, _timer]

## 疲劳满足度（1=精神饱满，0=精疲力竭）。无 Needs 组件 / 无 fatigue 需求 → 返回 1.0（不影响行为）。
## 此处只读不写：将来若加「睡觉恢复疲劳」，让 rest 状态调用 Needs.restore("fatigue", …) 即可，本函数不动。
func _fatigue_ratio() -> float:
	var needs_comp := creature.get_component(Needs) as Needs
	if needs_comp == null:
		return 1.0
	var fn := needs_comp.need_by_id("fatigue")
	if fn == null:
		return 1.0
	return fn.ratio()

## 睡觉恢复疲劳：处于「休息」状态时按速率回复（需 Needs + fatigue 需求，缺则不动）。
## 走 Needs.restore() 协议，不认识它的内部结构；将来「吃/喝」也走同一个入口。
func _recover_while_resting(dt: float) -> void:
	if last_drive != "rest":
		return
	var needs_comp := creature.get_component(Needs) as Needs
	if needs_comp == null:
		return
	needs_comp.restore("fatigue", SLEEP_RECOVER_RATE * dt)
