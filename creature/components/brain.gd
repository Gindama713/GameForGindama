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
##   Flee     逃命   看见玩家（`Perception.threats()`）时 12.0；选中 → 背离威胁走 + 请求疾跑
##   Huddle   抱团   夜里越冷、身边越空时越重；选中 → 朝同类重心挪一步（挤在一起取暖，见 `Thermal`）
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

## —— 逃命（flee，2026-09-20 加）——
## 【为什么需要它】用户要求"动物也能疾跑，好更快逃离危险"。但**"危险"必须有个来源**：
##   本项目的 `Perception.neighbors()` 只返回**同物种**邻居（猪只能看见猪）——
##   所以在此之前，猪**根本不知道玩家在旁边**，疾跑给它们也没用。
##   现在 `Perception.threats()` 把「玩家且没藏起来」算作威胁（见 perception.gd），
##   本驱动据此让猪朝反方向跑、并请求 Sprint。
##
## 【为什么权重必须压过 rest】夜间 rest 权重 ≈ 3.0+NIGHT_REST_BONUS(3.0) ≈ 6.0。
##   若 flee 只有 2~3，就会出现"被追着还站在原地睡觉"的滑稽场面。
##   FLEE_GAIN 取 12.0：> 夜间休息、也 > 渴到危险档的 drink(≈12.8) 同一量级 ——
##   逃命是最高优先级的活命行为，但不该让猪渴死，故两者接近、由随机兜底区分。
const FLEE_GAIN := 12.0
## 逃命时的决策间隔倍率（压到一半 —— 被追时犹豫 0.8 秒是致命的）。
const FLEE_DECIDE_MULT := 0.5
## 威胁记忆时长（游戏分）：威胁消失后仍继续跑一小段。
## 【为什么需要】猪每格只走 1 步、决策间隔又是 0.4~1 秒，
##   若"这一帧没威胁"就立刻停下，会出现"跑一步 → 停 → 玩家追上 → 再跑一步"的抽搐。
##   记忆让它跑出一段像样的距离，而不是贴着玩家原地挪。
const FLEE_MEMORY := 3.0
## 脱力（跑空了）时逃命权重的折扣。
## 【为什么只降不禁止】跑不动的猪仍然该**走**开（常速），只是不再着急。
##   若把 flee 权重清零，会变成"猪被追到脱力后忽然原地开始吃草"的诡异画面。
const FLEE_EXHAUSTED_DAMP := 0.6
## 逃命时"我想跑"门闩的**最短**保持时长（游戏分）。见 `_want_sprint` 的说明。
## 实际取 `max(决策间隔, 本值)` —— 决策间隔本身就够长时以它为准，
##   避免出现"门闩比决策还短 -> 中间有帧没举意 -> 跑一格停一格"。
const FLEE_SPRINT_HOLD := 0.5

## —— 抱团取暖（huddle，2026-09-21 加）——
## 【为什么需要它】用户的机制是「夜里变冷 → 猪**倾向抱团** → 挤在一起掉得慢」。
##   "掉得慢"由 `Thermal` 负责（按邻近数减免流失），但**"倾向抱团"必须有人推动** ——
##   光有减免是不够的：夜里 `rest` 权重 ≈3.4 会让猪**就地睡下**，
##   它们不会主动挪到一起，于是"抱团"永远只发生在**碰巧**挨着的那几对身上。
##
## 【取值 5.0 —— 实测调出来的，不是估的】（4 只猪 / 空地 / 整夜 600 分 / 种子 20260918）
##
##   | HUDDLE_GAIN | 平均邻近 | 天亮保暖 | 休息时间占比 |
##   |---|---|---|---|
##   | 0（对照，等于没有本驱动） | 1.29 | 57.6 | 93% |
##   | 3.5 | 1.81 | 64.5 | 93% |
##   | 5.0 | **2.07** | **67.9** | 94% |
##   | 10.0 | 1.92 | 65.9 | 93% |
##
##   （独猪基准：0 只邻近、天亮保暖 40）
##   ⇒ 取 5.0：明显优于 3.5，而 10.0 已经没有更多收益（在 1.8~2.1 之间震荡，是噪声）。
##
##   ⚠ **我一开始写在这里的警告是错的，实测推翻了它**。原文写的是
##     "权重取太大（>6）会让猪整夜躁动、不再睡 -> 疲劳回不上来"。
##     实测到 20.0 为止，**休息时间占比始终是 93~94%**，与权重完全无关。
##     原因：本驱动"走不动就地休息"（见下面 match 分支）—— 猪挪到同伴身边就睡下，
##     所以它**结构上不可能**挤掉睡眠。教训：这类"权重会不会压垮另一个驱动"的担忧，
##     要先看那个驱动是**按时间买断**的（`rest` 一次买 60~150 分）还是**按次**的 ——
##     买断型的极难被挤掉，估权重之前该先算这笔账，而不是先写一条警告。
##
##   ⚠ 真正需要担心的不是睡眠，而是**机会太少**：夜里 94% 的时间在睡，
##     醒着的窗口很碎，一次决策只走 1 格 -> 光加权重最多推到 1.9 就上不去了。
##     所以本驱动与 feed/drink 一样接了 `TRAVEL_STICKY`（见那里的注释）——
##     粘性才是把它从 1.29 推到 2.07 的主因，权重只是次要项。
const HUDDLE_GAIN := 5.0

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
var _flee_memory: float = 0.0       # 威胁消失后仍继续逃的剩余时间（见 FLEE_MEMORY）
## 「我想跑」的门闩，由决策点置位、由 `tick()` 每帧举给 Sprint。
## 【为什么需要门闩】`_decide_and_act()` 每 0.4~1 秒才跑一次，
##   而 `Sprint` 的意图位**每帧重置** —— 不锁的话，决策后第二帧意图就丢了、猪只跑一格。
var _want_sprint := false
var _sprint_hold := 0.0             # 门闩还能保持多久（游戏分）

func requires() -> Array:
	return [GridMover]              # 硬依赖：没有移动组件就无从行动

func setup(host: Node) -> void:
	super.setup(host)
	last_drive = "wander"
	_sticky_drive = ""
	_sticky_left = 0
	_flee_memory = 0.0
	_want_sprint = false
	_sprint_hold = 0.0
	_reset_timer()

func tick(dt: float) -> void:
	# 不判断生死 —— 死了就不会被 tick（Creature.die() 已把宿主摘出时钟）
	_flee_memory = maxf(_flee_memory - dt, 0.0)     # 威胁记忆随真实时间衰减
	_sprint_hold = maxf(_sprint_hold - dt, 0.0)
	if _sprint_hold <= 0.0:
		_want_sprint = false
	# 把门闩举给 Sprint。**每帧都要举**（Sprint 的意图位每帧清空）。
	# 【与体力脱力的配合】`request(true)` 只管举意，跑不跑得动由 Sprint 自己判 ——
	#   跑空的猪会自动变成"常速逃"，这正是"追累了能咬死"的机制。
	if _want_sprint:
		var sp := creature.get_component(Sprint) as Sprint
		if sp != null:
			sp.request(true)
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
	## 同物种邻居（社交 / 抱团共用）。**一帧只扫一次** ——
	## `perc.neighbors()` 要扫 (2×6+1)²=169 格，加抱团驱动时若再调一遍就是白扫两次。
	var ns: Array = []
	var perc := creature.get_component(Perception) as Perception
	if perc != null:
		ns = perc.neighbors()
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

	# 逃命（flee，2026-09-20）—— 需要 Perception（看得见威胁）+ Sprint（跑得动）。
	# 【代价】`threats()` 只遍历 `"player"` 组的成员（**不是全生物表**），O(1) 级别；
	#   且本函数只在**决策点**被调用（不是每帧），所以可以放心查。
	#   与之相对，`Sprint.tick()` 是每帧的 —— 所以那边的体力读取必须 O(1)（它确实只读一条需求）。
	var flee_w := 0.0
	var flee_dir := Vector2.ZERO
	var sprint := creature.get_component(Sprint) as Sprint
	if perc != null:
		var threats := perc.threats()
		if not threats.is_empty():
			_flee_memory = FLEE_MEMORY          # 看见威胁 -> 续期记忆
			flee_dir = _dir_from_nearest(threats)   # 背离最近的那个威胁
			flee_w = FLEE_GAIN
		elif _flee_memory > 0.0:
			# 记忆期：威胁暂时看不见了（玩家被高草藏起来 / 走远了），但余势还在。
			# 【为什么不记住方向】记住的向量早已过时 —— 猪会朝一个空方向跑很远。
			#   这里退化为**普通游荡 + 半个权重**（"往远处遛"而不是"原地等被追"）：
			#   用一个随机方向，仍然是"在动"而不是站着。
			flee_dir = _rand_dir()
			flee_w = FLEE_GAIN * 0.5
	# 体力见底 -> 逃命意愿稍降（跑不动了，一直朝墙撞没意义）。
	# 注意：这里**不阻止逃命**，只是降低权重 —— 猪仍然会常速走开，只是不再那么急。
	if flee_w > 0.0 and sprint != null and sprint.is_exhausted():
		flee_w *= FLEE_EXHAUSTED_DAMP

	# 抱团取暖（huddle，2026-09-21）—— 见 HUDDLE_GAIN 的注释。
	# 【意愿与目标分开取，这不是重复】"想不想挤"问 `Thermal`（它知道昼夜、冷暖、身边有几具身体），
	#   "往哪挤"用同物种邻居 `ns`（想挨的是同类，不是随便一只什么生物）。
	#   两件事的来源不同：`Thermal` 的邻近数是**不分物种**的物理取暖（挨着谁都能暖），
	#   而**去挤谁**是行为选择 —— 猪会挤猪，不会专程去挤一只兔子。
	var huddle_w := 0.0
	var huddle_dir := Vector2.ZERO
	var thermal := creature.get_component(Thermal) as Thermal
	if thermal != null and not ns.is_empty():
		var urge := thermal.huddle_urge()
		if urge > 0.0:
			huddle_w = urge * HUDDLE_GAIN
			huddle_dir = _dir_to_centroid(ns)

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
		elif _sticky_drive == "huddle":
			# 【抱团也要粘性，理由与 feed/drink 同源，但病因不同】
			#   feed/drink 的病是"两个等重目标互相拉锯"；
			#   抱团的病是"**一次决策只走 1 格，而一次休息买 60~150 分**" ——
			#   夜里约 85% 的时间在睡，醒着的窗口很碎，猪挪一步就又睡下，
			#   于是"往同伴那边走"永远走不出两三格。
			#   实测（4 只猪、空地、整夜）：权重从 3.5 一路加到 20，
			#   平均邻近数都卡在 1.5~1.9 上不去 —— 说明瓶颈不在权重，而在**机会太少**。
			#   给粘性后，一旦决定去抱就连着走几步，把距离真正走掉。
			if huddle_w > 0.0:
				huddle_w *= TRAVEL_STICKY
			else:
				_sticky_left = 0          # 已经抱到了 -> 目标消失，粘性立刻失效

	# --- 加权随机（轮盘）选一个驱动 ---
	# 【为什么写成"id 与权重**成对**"而不是两个平行数组】（2026-09-21 改）
	#   两个平行数组靠**下标对齐**，顺序错一位**不会报任何错** ——
	#   只会把 A 驱动的权重喂给 B 驱动，是典型的**静默失败**
	#   （正是 `DefValidator` 想消灭的那一类：数据错了却没人喊）。
	#   写成对之后，`id` 和它的权重在结构上**不可能错位**。
	#   ⚠ 加第 11 个驱动仍然要改 `match chosen` 的分支（那是行为、不是数据，收不进来），
	#     但"权重配错对象"这一种错法从此不存在了。
	#   ⚠ 顺序不影响正确性（轮盘是加权随机），但**保持与 `match` 分支同样的书写顺序**便于对照。
	var drive_table: Array = [
		["wander", wander_w], ["social", social_w], ["separate", separate_w],
		["rest", rest_w], ["idle", idle_w], ["feed", feed_w],
		["cling", cling_w], ["drink", drink_w], ["flee", flee_w], ["huddle", huddle_w],
	]
	var chosen := _roulette(drive_table)
	_update_sticky(chosen, feed_w, drink_w, huddle_w)
	match chosen:
		"flee":
			# 逃命：朝背离威胁的方向跑一格。
			# 【疾跑意图由 `tick()` 每帧举】见 `_want_sprint` —— 本函数只在决策点跑
			#   （每 0.4~1 秒一次），而 Sprint 的意图位是**每帧重置**的，
			#   所以这里只做"决定要不要跑"，不直接 request。
			_want_sprint = true
			_sprint_hold = maxf(_timer, FLEE_SPRINT_HOLD)   # 门闩至少撑到下一次决策
			if not _step_toward(mover, dirs, flee_dir):
				_wander_step(mover, dirs)      # 无路可逃（被围死）-> 退化游荡
			else:
				last_drive = "flee"
		"cling":
			_step_toward(mover, dirs, cling_dir)   # 朝妈走一步（走不动/已在身边=站着陪妈）
			last_drive = "cling"
		"huddle":
			# 朝同类重心挪一步（挤到一起取暖）。
			#
			# ⚠ **走不动时绝不退化游荡**（这里与 social/separate/feed 的处理**故意不同**）。
			#   实测踩过：`_step_toward` 失败有两种情形 ——
			#     ① 重心方向为零（已经挤在中间了）
			#     ② 目标格被同伴占着（已经挨着同伴了）
			#   这两种都是"**已经抱到了**"的正面信号，退化游荡会把刚聚起来的一群**又拆散**，
			#   于是"抱团"永远聚不起来（实测：4 只猪在空地过一夜，平均只挨着 1.1 只，
			#   而理论值应该是 3 只）。
			#   ⇒ 正确反应是**就地歇下**（`last_drive = "rest"`）：想抱、已经抱到了、那就睡。
			#     这同时也让"抱团"与"睡觉"自然接续 —— 猪挪到同伴身边就趴下，
			#     而不是到了旁边再随机走开。
			if _step_toward(mover, dirs, huddle_dir):
				last_drive = "huddle"
				return
			last_drive = "rest"
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
## 只在目标**还没满足**（权重 > 0）时才续期 —— 吃饱/喝足/已抱到会自动放手，不需要额外复位。
func _update_sticky(chosen: String, feed_w: float, drink_w: float, huddle_w: float) -> void:
	_sticky_left = maxi(_sticky_left - 1, 0)
	if chosen == "feed" and feed_w > 0.0:
		_sticky_drive = "feed"
		_sticky_left = TRAVEL_STICKY_STEPS
	elif chosen == "drink" and drink_w > 0.0:
		_sticky_drive = "drink"
		_sticky_left = TRAVEL_STICKY_STEPS
	elif chosen == "huddle" and huddle_w > 0.0:
		_sticky_drive = "huddle"
		_sticky_left = TRAVEL_STICKY_STEPS

func _rand_dir() -> Vector2:
	var d: Vector2i = GridMover.DIRS[creature.rng.randi_range(0, GridMover.DIRS.size() - 1)]
	return Vector2(d)

## 加权随机选一项（轮盘）。权重 ≤0 的项不会被选中。
## `table` 的每一项是 `[id: String, weight: float]` —— **成对**传入，理由见调用点的注释。
func _roulette(table: Array) -> String:
	var total := 0.0
	for item in table:
		if float(item[1]) > 0.0:
			total += float(item[1])
	if total <= 0.0:
		return String(table[0][0])          # 全为 0 -> 退回第一项（与旧行为一致）
	var r: float = creature.rng.randf() * total
	var acc := 0.0
	for item in table:
		var w := float(item[1])
		if w <= 0.0:
			continue
		acc += w
		if r < acc:
			return String(item[0])
	return String(table[table.size() - 1][0])

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

## 决策间隔：移动类带抖动；发呆=短歇；休息=一段（有上限）睡眠；**被减速时移动间隔等比放大**。
##
## 【速度定义域只有一处 —— 2026-09-20 统一】
##   从前本函数自己算「`aging.speed_factor()` × 疲劳放大」这套减速，
##   而 PlayerBrain 走的是 `Creature.locomotion_speed()`（协议 6 聚合值）——
##   **同一事实两套算法**：把 Aging 或 Needs 的系数调了，AI 与主角会朝不同方向漂移
##   （最坏情况：调慢疲劳后 AI 变慢、主角没变，且没人看得出是哪一处生效）。
##   现在统一为：**`Creature.current_speed()` 是唯一的"速度聚合"入口**（含减益与疾跑增益），
##   Brain 只把它换算成决策间隔（越慢 → 间隔越长），不再认识 Aging / Needs / Sprint 的内部系数。
##   协议 6 的每个实现者（Aging 的幼老、Needs 的疲劳、Body 的断腿）各自贡献一份减速；
##   协议 6b 的实现者（Sprint）贡献加速。
##
## ⚠ 与「性格/抖动」的分工：`energy`（活力）与 `JITTER`（随机）是 **Brain 独有的决策节奏**，
##   不属于"移动速度"，物理上没法从 current_speed 推出来 → 仍留在本函数里。
func _reset_timer() -> void:
	var base := 1.0
	if creature.def != null and creature.def.move_interval > 0.0:
		base = creature.def.move_interval
	# 只认协议 6/6b 的聚合值：1.0 = 满速（间隔不变）；0.63 = 幼崽 → 间隔 ×1.59；
	# 2.0 = **疾跑中** → 间隔 ×0.5（逃命时决策得更勤，否则冲刺白加）。
	# ⚠ 显式标 float：`creature` 在组件基类里是 `Node`，取到的是 Variant（坑 7）。
	var speed: float = creature.current_speed()
	base *= 1.0 / maxf(speed, 0.1)    # 下限保护：动不了时别把间隔乘到无穷（0.1 → 最多 ×10）

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
		"flee":
			# 逃命：**间隔再压一半** —— 被追的时候犹豫 0.8 秒是致命的。
			# 不用 randf 抖动（逃跑节奏要稳，不能"跑一格发呆一下"）。
			t = base * FLEE_DECIDE_MULT
		_:
			# 移动类：活力高更频繁；再加抖动 → 步频不规律。
			# 疲劳的减速已由 current_speed()（Needs.move_speed_factor）贡献，此处不再重复乘。
			t = base * (1.6 - energy) * creature.rng.randf_range(1.0 - JITTER, 1.0 + JITTER)
	_timer = maxf(t, 0.15)

## 调试自述（生成日志 + 调试器检查器里的 debug/components/brain 行）
func debug_state() -> String:
	return "上次=%s 下次 %.1fs" % [last_drive, _timer]

## 疲劳满足度（1=精神饱满，0=精疲力竭）。无 Needs 组件 / 无 fatigue 需求 → 返回 1.0（不影响行为）。
## ⚠ 只用于**睡眠时长**（rest 越想睡越久）——**不再用于移动减速**：
##   移动减速走协议 6（`Needs.move_speed_factor()` 经 `Creature.locomotion_speed()` 聚合）。
##   两处用途不同，不是重复定义：一个是"睡多久"，一个是"动多慢"。
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
