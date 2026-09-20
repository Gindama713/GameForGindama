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
##   Rest     休息   权重 = (1−活力)×0.5+(1−疲劳)×0.8+夜晚 3.0；选中 → 白天短歇、夜里长睡（睡回疲劳）
##   Idle     发呆   权重 = 基线 + (1−活力)；选中 → 原地**短歇**（让「走」不再连续）
##   Feed     觅食   权重 = 饥饿度 × 4.0（且附近有嫩草）；选中 → 站草上啃 / 朝草走
##   Drink    饮水   权重 = 口渴度换算（`Drinking.thirst_weight()`，渴到危险再 ×1.6）；
##                    选中 → 已在水边就**站住**（`Drinking` 自会连续补水），否则朝最近**岸格**走一步
##   Cling    跟妈   幼崽且母亲活着、离得 ≥2 格时 3.0；选中 → 朝妈走
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
const REST_WEIGHT := 0.5           # 白天想歇的倾向（调低 → 白天更活跃；与夜里拉开反差）
const FATIGUE_REST_WEIGHT := 0.8   # 疲劳→休息意愿（减速而非致命，见 need_def.gd 注释）
const IDLE_BASE := 0.35            # 发呆基线（保证「走」有间隙，不至于一直动）
const IDLE_LOW_ENERGY := 0.6       # 低活力更爱站着发呆
const NIGHT_REST_BONUS := 3.0      # 夜晚→休息加权（远大于白天 → 夜里基本都在睡）
const FATIGUE_SLOW_FACTOR := 1.5   # 疲劳→移动间隔放大（越累动得越稀）
const SLEEP_RECOVER_RATE := 0.2    # 休息/睡觉时疲劳回复速率（游戏分钟）
const FATIGUE_ID := "fatigue"      # 用哪个需求当「疲劳」—— Brain 唯一需要的需求 id（别再散写字符串）
## 觅食驱动权重 = 饥饿度(0..1) × FEED_GAIN。
## **已实测调过**：4.0 时权重被轮盘摊薄 -> 饿着的猪也只有约 1/3 的决策朝草走；
##   而"一次休息"买 60~150 游戏分的静止、"一次移动"只买 1 格 -> **时间账上永远被休息压死**，
##   结果走不完"草场 ↔ 湖"那 70~90 格的通勤、活活饿死在半路（实测 5/5）。
##   提到 10.0：饿了的猪专心去吃饭（低饥饿时权重仍很小，不影响平时的行为分布）。
const FEED_GAIN := 10.0
const CLING_WEIGHT := 3.0          # 幼崽"跟妈"驱动权重（< 饿极了的 feed≈4，故很饿会先去吃再回妈身边）[占位]

## 【旅行粘性 —— 2026-09-20 新增，修的是"猪原地拉锯、哪边都到不了"】
##   `feed` 与 `drink` 是一对**近乎等重**的驱动：口渴(0.07/分)只比饥饿(0.05/分)快一点点，
##   于是两者的权重长期咬在伯仲之间。而**一次决策只走 1 格**（约 2~4 游戏分），
##   草与水又相距十几格 -> 猪被卡在两地中间来回拉锯：朝草一步、朝水一步，**净位移 ≈ 0**。
##   实测（种子 20260918，8 只猪，1800 游戏分）：
##     驱动占比 feed 25.6% / drink 25.6% · 站在可食草上只占 **3.7%** 的时间 ·
##     离可食草恒为 ~15 格、离水恒为 ~8 格 -> 净啃口数只够需求的一半，**全员饿死**。
##   解法：给"已经在赶路/已经在吃"的那个目标加**粘性** —— 下一次决策继续偏向它，
##   直到目标达成（吃饱 / 喝足时该驱动的权重自然归零，粘性随之失效，无需额外复位）。
##   ⇒ 猪变成"走到草上吃饱 -> 渴了走到岸边喝满 -> 再回来吃"，而不是原地拉锯。
##   ⚠ 粘性有步数上限：目标不可达时不会永久卡死（到点就恢复常规轮盘）。
const TRAVEL_STICKY := 4.0         # 粘住的目标驱动：权重 ×该值
const TRAVEL_STICKY_STEPS := 12    # 粘性最多维持这么多次决策

## 休息时长（游戏分钟）：白天是「短歇」、夜里是「长睡」（用户 2026-09-19 拍板「拉开昼夜反差」）
const REST_DAY_MIN := 1.5
const REST_DAY_MAX := 5.0
const REST_NIGHT_MIN := 60.0
const REST_NIGHT_MAX := 150.0
const JITTER := 0.35               # 移动间隔的随机抖动比例（步频不规律）

var _timer: float = 0.0
var last_drive: String = "wander"   # 上一次决策选中了什么（调试/检视面板用）
var _sticky_drive: String = ""      # 正在"粘住"的目标驱动（feed / drink；见 TRAVEL_STICKY）
var _sticky_left: int = 0           # 粘性还剩几次决策

func requires() -> Array:
	return [GridMover]              # 硬依赖：没有移动组件就无从行动

func setup(host: Node) -> void:
	super.setup(host)
	last_drive = "wander"
	_sticky_drive = ""
	_sticky_left = 0
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

	# 觅食（可选组件 Grazing；没有就不产生 feed 驱动）
	var feed_w := 0.0
	var feed_dir := Vector2.ZERO
	var graze := creature.get_component(Grazing) as Grazing
	if graze != null:
		var hw := graze.hunger_weight()              # 先算饥饿度（便宜）
		if hw > 0.0 and graze.has_nearby_forage():   # 饿了才费钱去扫草格
			feed_w = hw * FEED_GAIN
			feed_dir = graze.forage_dir()

	# 跟妈（cling）：仅**幼崽**且母亲活着、离得≥2格时高权重朝妈走；挨着妈就松散跟随（不强制）
	var cling_w := 0.0
	var cling_dir := Vector2.ZERO
	var ag := creature.get_component(Aging) as Aging
	var lin := creature.get_component(Lineage) as Lineage
	if ag != null and lin != null and ag.stage() == Aging.Stage.JUVENILE:
		var mom := lin.mother()
		if mom != null and mom.is_alive():
			var d: Vector2i = mom.coord - creature.coord
			if float(d.length()) >= 2.0:
				cling_w = CLING_WEIGHT
				cling_dir = Vector2(d).normalized()

	# 饮水（可选组件 Drinking；没有就不产生 drink 驱动）
	# 【为什么方位不在这里算】thirst_weight() 便宜（只读需求），而 water_dir() 要遍历水格表（贵）
	#   -> 方位只在"真的选中 drink"的分支里才算。
	var drink_w := 0.0
	var drink := creature.get_component(Drinking) as Drinking
	if drink != null:
		drink_w = drink.thirst_weight()

	# --- 旅行粘性：把"正在赶路的目标"抬起来（详见 TRAVEL_STICKY 的注释）---
	if _sticky_left > 0:
		if _sticky_drive == "feed":
			if feed_w > 0.0:
				feed_w *= TRAVEL_STICKY
			else:
				_sticky_left = 0          # 已吃饱 -> 目标消失，粘性立刻失效
		elif _sticky_drive == "drink":
			if drink_w > 0.0:
				drink_w *= TRAVEL_STICKY
			else:
				_sticky_left = 0          # 已喝足 -> 同上

	# --- 加权随机（轮盘）选一个驱动 ---
	var drives: Array[String] = ["wander", "social", "separate", "rest", "idle", "feed", "cling", "drink"]
	var weights: Array[float] = [wander_w, social_w, separate_w, rest_w, idle_w, feed_w, cling_w, drink_w]
	var chosen := _roulette(drives, weights)
	_update_sticky(chosen, feed_w, drink_w)
	match chosen:
		"cling":
			_step_toward(mover, dirs, cling_dir)   # 朝妈走一步（走不动/已在身边=站着陪妈）
			last_drive = "cling"
		"feed":
			# 站住开吃**问 Grazing**（口径必须唯一）。原版这里自己判 `is_edible`、而 Grazing 只啃 `is_tender`
			# → 猪站在满耐久草格上"站住了但啃不动"，永久卡死（实测踩过）。现在只认它一个判断：
			# **脚下可食就吃**（"嫩草优先"只影响"往哪走"，不影响"吃不吃"）。
			if graze != null and graze.can_eat_here():
				last_drive = "feed"
			elif not _step_toward(mover, dirs, feed_dir):
				_wander_step(mover, dirs)   # 走不动/已重合 → 退化游荡（下次再试）
			else:
				last_drive = "feed"
		"drink":
			# 已在岸边 → 站着（Drinking.tick 自会连续补水）；否则朝最近的**岸格**走一步。
			# 注意走的是"岸格"不是"水格"：水不可踩，朝水格走最后一步必被拒 → 会原地抖动。
			if drink == null:
				_wander_step(mover, dirs)                  # 没挂 Drinking（权重>0 时不可能，兜底）
			elif drink.at_water():
				last_drive = "drink"
			elif not _step_toward(mover, dirs, drink.water_dir()):
				_wander_step(mover, dirs)                  # 走不动/找不到岸格 → 退化游荡（下次再试）
			else:
				last_drive = "drink"
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

## 记录"这次选的目标驱动"，让下一次决策继续偏向它（粘性）。详见 TRAVEL_STICKY 的注释。
## 只在目标**还没满足**（权重 > 0）时才续期 —— 吃饱/喝足会自动放手，不需要额外复位。
func _update_sticky(chosen: String, feed_w: float, drink_w: float) -> void:
	_sticky_left = maxi(_sticky_left - 1, 0)
	if chosen == "feed" and feed_w > 0.0:
		_sticky_drive = "feed"
		_sticky_left = TRAVEL_STICKY_STEPS
	elif chosen == "drink" and drink_w > 0.0:
		_sticky_drive = "drink"
		_sticky_left = TRAVEL_STICKY_STEPS

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
	var aging := creature.get_component(Aging) as Aging
	if aging != null:
		base *= aging.speed_factor()      # 幼崽/老年决策更慢（年龄影响行为节奏）

	var energy := 0.5
	var person := creature.get_component(Personality) as Personality
	if person != null:
		energy = person.get_trait("energy")
	var fr := _fatigue_ratio()

	var t: float = base
	match last_drive:
		"rest":
			# 白天=短歇、夜里=长睡（很少醒）；越累睡得越久
			var at_night := TimeSystem.is_night()
			var lo: float = REST_NIGHT_MIN if at_night else REST_DAY_MIN
			var hi: float = REST_NIGHT_MAX if at_night else REST_DAY_MAX
			t = creature.rng.randf_range(lo, hi) * (1.0 + (1.0 - fr) * 0.5)
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
	var fn := needs_comp.need_by_id(FATIGUE_ID)
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
	needs_comp.restore(FATIGUE_ID, SLEEP_RECOVER_RATE * dt)
