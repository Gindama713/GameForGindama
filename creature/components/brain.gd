class_name Brain
extends CreatureComponent

## 融合式大脑（v2，2026-09-19）—— 用「加权随机（轮盘）」在多个行为驱动中挑一个。
##
## 为什么改：v1 是「比大小取最大」，结果是**确定性的** —— 高活力猪永远游荡（像发疯）、
## 低活力猪一到夜里就一直静止（像死掉）。改为轮盘后：**性格只调「概率」，具体选谁随机**，
## 于是同一只猪也会走走停停、偶尔发呆；不同个体倾向不同（有的爱动、有的爱歇）。
##
## 驱动（权重全是占位值，跑出来再调）：
##   Wander   游荡   权重随「活力」上升
##   Social   合群   附近有同类时 = 合群度，朝邻居重心走（凝聚）
##   Separate 独处   附近有同类时 = 1−合群度，背离最近邻居（分离）
##   Rest     休息   权重 = (1−活力)+(1−疲劳)+夜晚加权；选中 → 原地不动（并睡回疲劳）
##   Idle     发呆   权重 = 基线 + (1−活力)；选中 → 原地**短歇**（让「走」不再连续）
##
## 时长也不固定：移动类带抖动、发呆是短歇、休息是**一段有上限的睡眠**（会醒，不是永久静止）。
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
const IDLE_BASE := 0.35            # 发呆基线（保证「走」有间隙，不至于一直动）
const IDLE_LOW_ENERGY := 0.6       # 低活力更爱站着发呆
const NIGHT_REST_BONUS := 1.5      # 夜晚→休息加权（轮盘下≈大部分时间在歇，但会偶尔翻动）
const FATIGUE_SLOW_FACTOR := 1.5   # 疲劳→移动间隔放大（越累动得越稀）
const SLEEP_RECOVER_RATE := 0.2    # 休息/睡觉时疲劳回复速率（游戏分钟）

## 一次休息（睡眠）的时长范围（游戏分钟）；到点会醒，不是永久静止
const REST_MIN := 4.0
const REST_MAX := 14.0
const JITTER := 0.35               # 移动间隔的随机抖动比例（步频不规律）

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
	var fatigue_ratio := _fatigue_ratio()

	# --- 各驱动权重：只是「倾向」，最终由加权随机决定 → 性格影响概率、行为随机 ---
	var wander_w := WANDER_BASE + energy * WANDER_ENERGY
	var rest_w := (1.0 - energy) * REST_WEIGHT + (1.0 - fatigue_ratio) * FATIGUE_REST_WEIGHT
	if TimeSystem.is_night():
		rest_w += NIGHT_REST_BONUS
	var idle_w := IDLE_BASE + (1.0 - energy) * IDLE_LOW_ENERGY

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

	# --- 加权随机（轮盘）选一个驱动 ---
	var drives: Array[String] = ["wander", "social", "separate", "rest", "idle"]
	var weights: Array[float] = [wander_w, social_w, separate_w, rest_w, idle_w]
	match _roulette(drives, weights):
		"social":
			if _step_toward(mover, dirs, social_dir):
				last_drive = "social"
				return
			_wander_step(mover, dirs)      # 无邻居/已重合 → 退化为游荡
		"separate":
			if _step_toward(mover, dirs, separate_dir):
				last_drive = "separate"
				return
			_wander_step(mover, dirs)
		"rest":
			last_drive = "rest"            # 原地休息（睡觉）
		"idle":
			last_drive = "idle"            # 原地发呆（短歇）
		_:
			_wander_step(mover, dirs)

func _wander_step(mover: GridMover, dirs: Array[Vector2i]) -> void:
	_step_toward(mover, dirs, _rand_dir())
	last_drive = "wander"

func _rand_dir() -> Vector2:
	var d: Vector2i = GridMover.DIRS[creature.rng.randi_range(0, GridMover.DIRS.size() - 1)]
	return Vector2(d)

## 加权随机选一项（轮盘）。权重 ≤0 的项不会被选中。
func _roulette(drives: Array, weights: Array) -> String:
	var total := 0.0
	for w in weights:
		if float(w) > 0.0:
			total += float(w)
	if total <= 0.0:
		return String(drives[0])
	var r: float = creature.rng.randf() * total
	var acc := 0.0
	for i in drives.size():
		var w := float(weights[i])
		if w <= 0.0:
			continue
		acc += w
		if r < acc:
			return String(drives[i])
	return String(drives[drives.size() - 1])

## 朝 desired 方向走一格；desired 为零向量时返回 false。
func _step_toward(mover: GridMover, dirs: Array[Vector2i], desired: Vector2) -> bool:
	if desired.length_squared() < 0.0001:
		return false
	return mover.try_step(_pick_best(desired, dirs))

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

## 决策间隔：移动类带抖动；发呆=短歇；休息=一段（有上限）睡眠；越累移动越慢。
func _reset_timer() -> void:
	var base := 1.0
	if creature.def != null and creature.def.move_interval > 0.0:
		base = creature.def.move_interval

	var energy := 0.5
	var person := creature.get_component(Personality) as Personality
	if person != null:
		energy = person.get_trait("energy")
	var fr := _fatigue_ratio()

	var t: float = base
	match last_drive:
		"rest":
			# 一次睡一段（会醒）；越累睡得越久
			t = creature.rng.randf_range(REST_MIN, REST_MAX) * (1.0 + (1.0 - fr) * 0.5)
		"idle":
			t = base * creature.rng.randf_range(0.4, 3.0)
		"blocked":
			t = base * 0.5
		_:
			# 移动类：活力高更频繁；疲劳低更慢；再加抖动 → 步频不规律
			t = base * (1.6 - energy) * creature.rng.randf_range(1.0 - JITTER, 1.0 + JITTER)
			if fr < 1.0:
				t *= 1.0 + (1.0 - fr) * FATIGUE_SLOW_FACTOR
	_timer = maxf(t, 0.15)

## 调试自述（生成日志 + 调试器检查器里的 debug/components/brain 行）
func debug_state() -> String:
	return "上次=%s 下次 %.1fs" % [last_drive, _timer]

## 疲劳满足度（1=精神饱满，0=精疲力竭）。无 Needs 组件 / 无 fatigue 需求 → 返回 1.0（不影响行为）。
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
