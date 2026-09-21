class_name Thermal
extends CreatureComponent

## 体温组件（2026-09-21）—— 管「保暖」这条需求在**昼夜**与**抱团**下的涨落。
##
## ── 用户拍板的设计（2026-09-21）──
##   · 白天（**不下雨的话**）= 满的；夜里**逐渐**变冷。
##   · 猪倾向**抱团**：周围同伴越多，掉得越慢。
##   · **非冬天**，一只猪独自睡一夜**不会死**，只是"有点冷"（保暖偏低）。
##   · 人同理。
##
## ── 为什么独立成组件，而不是写进 Needs ──
##   `Needs` 是**通用**的匀速衰减器（读 `NeedDef.drain_rate` 就完事，不认识任何具体需求）。
##   而"保暖"要问**昼夜**（`TimeSystem`）、要数**邻居**（`Perception`）——
##   这两件事都超出了"匀速衰减"的语义。塞进 `Needs` 就变成在通用件里特判某一个 id，
##   正是本项目反复避免的写法（见 needs.gd 的纪律注释）。
##   ⇒ 与 `Sprint` 同一个套路：**专用速率归专用组件**，`Needs` 只管通用基线。
##   ⚠ **配套改动**：`need_warmth.tres` 的 `drain_rate` 必须改成 **0.0** ——
##     否则 `Needs.tick()` 会额外按基线扣一遍（"两把尺子量同一件事"，
##     与 `Sprint` 的 `DRAIN_PER_SEC` 注释里记的是同一条教训）。
##
## ── 涨落公式（唯一事实来源，调数值只动下面几个常量）──
##   冷度系数 `_cold_multiplier()`      —— 季节 / 下雨的接入点，当前恒 1.0
##   抱团减免 `_huddle_factor()`        —— `1 − min(邻近数 × 每只减免, 减免上限)`
##   夜里： `warmth -= NIGHT_DRAIN_PER_SEC × 冷度 × 抱团系数 × dt`
##   白天： `warmth += DAY_RECOVER_PER_SEC × dt`（封顶到 max_value）
##
## ── 数值为什么是这些（全部可复算）──
##   夜长 = 20:00 → 06:00 = 10 游戏小时 = **600 游戏分**（`TimeSystem.NIGHT_*`）。
##
##   | 邻近同伴 | 减免 | 一夜掉 | 天亮时剩 |
##   |---|---|---|---|
##   | 0 只（独猪） | 0% | 60.0 | **40.0**（"有点冷"，**不会死**） |
##   | 1 只 | 22% | 46.8 | 53.2 |
##   | 2 只 | 44% | 33.6 | 66.4 |
##   | 3 只 | 66% | 20.4 | 79.6 |
##   | ≥4 只 | 80%（上限） | 12.0 | **88.0** |
##
##   白天回满：`60 / 0.5 = 120 游戏分 = 2 游戏小时`（06:00 日出 → 08:00 回暖完毕）。
##   ⇒ **每晚掉多少、白天就回多少** → 稳态在 40↔100 之间震荡，**永远不会冻死**。
##     这正是"非冬天独猪不死"的**算术保证**，不是靠调参碰运气。
##
## ── 冬天怎么接（当前没有季节系统，所以留成**函数**而不是常量）──
##   让 `_cold_multiplier()` 在冬天返回 **2.0**：
##     独猪一夜掉 `600 × 0.1 × 2.0 = 120 > 100` → **冻死**；
##     抱团（×0.20）只掉 `24` → 活着。
##   ⇒ **"冬天必须抱团"的机制落点就在这里**，不需要再写第二条规则、也不动抱团代码。
##   同理"下雨"：让白天也返回 > 1 即可 —— 用户那句"白天当然**不下雨的话**"留的就是这个口子。
##   ⚠ 刻意**不做成常量** `WINTER_MULT := 1.0`：一个永远不参与计算的常量是死代码，
##     而一个"当前恒 1.0、但写明接入点"的函数是**接缝**。这是本项目既有的做法
##     （对照 `PlayerIntent.apply()` —— v1 直通，但接缝先立住）。

## 本组件的调试前缀（协议 3 的自述用）
const TAG := "体温"

## 用哪条需求当「保暖」。与 `Needs` 里的 id 同一个字面量（既有的债，见 needs.gd 注释）。
const WARMTH_ID := "warmth"

## 夜里每秒（= 每游戏分，见 time_system.gd 的 1:1 映射）掉多少保暖。
## 取 0.1 的理由见文件头表格：独猪一夜正好掉 60、剩 40 —— 冷但不死。
const NIGHT_DRAIN_PER_SEC := 0.1

## 白天每秒回多少保暖。0.5 → 掉 60 点只需 120 游戏分（2 游戏小时）回暖，
## 于是"天亮后不久就暖和了"，不会把早晨浪费在挨冻上。
const DAY_RECOVER_PER_SEC := 0.5

## 抱团判定半径（格）。2 格 = 5×5 邻域 —— "紧挨着"才算，不是"看得见"就算。
## ⚠ 不要用 `Perception.radius`(6)：那是"感知半径"（13×13），隔着一片草地也互相取暖，
##   抱团就失去意义了。两个半径是**不同的概念**，各有各的值。
const HUDDLE_RADIUS := 2

## 每多一只邻近同伴，冷度减免多少。
const HUDDLE_PER_NEIGHBOR := 0.22

## 减免上限：抱得再紧也留 20% 的冷。
## 【为什么必须留顶】否则"抱团"就从"省着点冷"变成了"免疫寒冷"——
##   冬天（冷度 2.0）会被这个上限挡住而失去惩罚，季节就白做了。
const HUDDLE_MAX_REDUCTION := 0.80

## 邻近数达到它就算"抱够了"，`huddle_urge()` 归零、大脑不再有抱团意愿。
## **与上面的减免公式同源**：`0.80 / 0.22 ≈ 3.64 → 取 4`，正是减免接近饱和的位置。
## ⚠ 写成字面量 4 而不是算式：GDScript 的 `const` 对 `ceil()` 这类内置函数的
##   常量折叠不可靠（会变成运行期求值而报错）。所以这里用注释锁住两者的关系 ——
##   **改 `HUDDLE_PER_NEIGHBOR` 或 `HUDDLE_MAX_REDUCTION` 时必须回来核对这个数。**
const HUDDLE_ENOUGH := 4

## 邻近数的重算间隔（游戏分）。
## 【为什么必须缓存】`Perception` 一次扫描是 `(2×6+1)² = 169` 格；本组件是**每帧** tick 的，
##   200 只生物 × 169 格 × 60 帧 ≈ 200 万次字典查询/秒 —— 直接吃掉小半个帧预算。
##   而"身边有几只猪"是**慢变量**（猪一次决策走 1 格、约 1 秒一次），
##   5 游戏分（= 5 真实秒）重算一次绰绰有余。
##   ⚠ 对照：`Brain` 里调 `neighbors()` 是安全的，因为它在**决策点**（0.4~1 秒一次）才跑。
##     本组件是每帧跑，所以必须自己缓存 —— 这是"谁在什么频率上调"决定的，不是风格问题。
const HUDDLE_REFRESH_MIN := 5.0

## 当前缓存的邻近生物数（抱团用）。由 `_refresh_huddle()` 定期刷新。
var _huddle_count: int = 0
var _refresh_left: float = 0.0

func requires() -> Array:
	# 硬依赖两条：
	#   Needs      —— 保暖值住在它那里（本组件只读写，不另存一份）
	#   Perception —— 数邻近同伴（**本组件不自己扫格**，否则就是第二份扫描实现）
	# 声明成硬依赖而不是"缺了就退化为 0"：那样会变成**静默失效**
	# （猪永远觉得孤单 → 永远最冷 → 看不出哪里配错了）。
	# 让 DefValidator 在启动期直接喊出来（"组件 Thermal 依赖 Perception，但本物种没挂它"）。
	return [Needs, Perception]

func setup(host: Node) -> void:
	super.setup(host)
	_huddle_count = 0
	# 错峰刷新：所有生物同一帧一起扫格会造成周期性卡顿（与 Grazing 的起手错峰同一考虑）。
	#
	# ⚠ **刻意不用 `host.rng`**，改用 `host.id` 派生 —— 这是实测踩出来的：
	#   第一版写的是 `host.rng.randf() * HUDDLE_REFRESH_MIN`，而 `creature.rng` 是
	#   **按创建顺序共享的一串数**：`Personality`/`Aging`(摇寿命)/`Lineage`(摇性别) 都在抽它。
	#   本组件排在它们中间，多抽一次 → **后面全部顺移一格** —— 实测猪的寿命从
	#   (6,7,5,5,6,6,6,6) 天变成 (6,7,5,5,6,5,5,6) 天。
	#   ⇒ **不需要随机性的组件就不要动这串数**（那是别人的种子预算），
	#     错峰这种"只要分散开就行"的需求，用自增 id 取模即可，效果一样且不打扰任何人。
	_refresh_left = float(host.id % 5) * (HUDDLE_REFRESH_MIN / 5.0)

# ---------------- 生命周期 ----------------

func tick(dt: float) -> void:
	var needs := creature.get_component(Needs) as Needs
	if needs == null:
		return
	var n := needs.need_by_id(WARMTH_ID)
	if n == null:
		return
	_refresh_huddle(dt)

	if TimeSystem.is_night():
		var loss := NIGHT_DRAIN_PER_SEC * _cold_multiplier() * _huddle_factor() * dt
		# 走 `Needs.drain()` 的**统一入口**（扣减 + 封底 + 见底日志只该有一处，见 needs.gd）。
		# 从前这里直接读写 `Need._depleted_logged`（私有字段）—— 现在本组件不再碰它。
		needs.drain(WARMTH_ID, loss, "冻僵了")
	else:
		if n.value >= n.def.max_value:
			return                       # 已经是满的，不必写也不必判
		var before := n.value
		n.value = minf(before + DAY_RECOVER_PER_SEC * dt, n.def.max_value)
		# 只在**跨过满值那一帧**报一次（否则每天会刷一屏）
		if before < n.def.max_value and n.value >= n.def.max_value:
			Log.ev("需求", "%s 暖和过来了（%s 回满）" % [creature.tag(), n.def.label])

# ---------------- 对外查询 ----------------

## 当前保暖比例（0..1）。无 Needs / 没挂 warmth 需求 → 1.0（视为"不冷"，不影响宿主）。
func warmth_ratio() -> float:
	var n := _warmth()
	return n.ratio() if n != null else 1.0

## 当前有多少只邻近同伴在帮我取暖（缓存值，每 `HUDDLE_REFRESH_MIN` 游戏分刷新一次）。
func huddle_count() -> int:
	return _huddle_count

## 当前受到的冷度减免（0..`HUDDLE_MAX_REDUCTION`）。0 = 一只都没有。
func huddle_reduction() -> float:
	return 1.0 - _huddle_factor()

## 夜里「想抱团」的**基础意愿**（哪怕还不冷）。
##
## 【为什么必须有一个底 —— 这是实测逼出来的】
##   第一版让意愿 = 有多冷 × 有多孤单。结果是：**入夜时保暖是满的 -> 意愿恰好为 0 ->
##   猪先自由散开**，等冷到能推动它们时，彼此已经离得很远，来不及再聚。
##   实测（4 只猪、空地、整夜）：每只平均只挨着 **1.09** 只同伴，而"挤成 2x2"应该是 3 只。
##   给一个底之后，`urge` 在入夜那一刻就有值，"天一黑就自然而然凑到一起"才成立 ——
##   这也更符合玩家的直觉（猪本来就会挤着睡，不是冷得受不了才挤）。
##
## 取 0.45：入夜（cold=0）时独猪意愿 0.45 -> 权重约 1.6，足以在睡眠的间隙里挪动，
##   又明显低于夜间 rest（约 3.4），所以**不会**让猪整夜不睡。
const URGE_FLOOR := 0.45

## 抱团意愿（0..1），供 `Brain` 的 huddle 驱动乘系数。与 `Grazing.hunger_weight()` 同一套分工：
## **本组件只给 0..1 的"想不想"，权重系数归 Brain**（`HUDDLE_GAIN`）。
##   0 = 不用抱（白天 / 身边已经够挤）
##   1 = 最想抱（深夜 + 快冻透了 + 身边一只都没有）
func huddle_urge() -> float:
	if not TimeSystem.is_night():
		return 0.0
	var n := _warmth()
	if n == null:
		return 0.0
	var cold := 1.0 - clampf(n.ratio(), 0.0, 1.0)
	# 冷度只用来"加成"，不用来"开关"：`URGE_FLOOR` 保证入夜就有意愿（见该常量注释）
	var want := URGE_FLOOR + (1.0 - URGE_FLOOR) * cold
	var alone := 1.0 - clampf(float(_huddle_count) / float(HUDDLE_ENOUGH), 0.0, 1.0)
	return want * alone

## 协议 3：调试自述。
func debug_state() -> String:
	if not TimeSystem.is_night():
		return "%s 白天 %.0f%%" % [TAG, warmth_ratio() * 100.0]
	return "%s 夜 保暖%.0f%% 邻近%d只 减免%.0f%% 一夜预计掉%.0f" % [
		TAG, warmth_ratio() * 100.0, _huddle_count,
		huddle_reduction() * 100.0, _night_drop_estimate()]

# ---------------- 内部 ----------------

## 按当前同伴数估算"这一夜还会掉多少"（**仅供调试自述**，不参与任何逻辑）。
## ⚠ 用**剩余**夜长而不是整夜 600 分：天已经过了一半就该报一半，
##   否则那个数字会在排查时误导人（"还剩 3 小时了却报整夜的量"）。
func _night_drop_estimate() -> float:
	return NIGHT_DRAIN_PER_SEC * _cold_multiplier() * _huddle_factor() * _night_minutes_left()

## 今夜还剩多少游戏分（夜 = [20:00, 24:00) ∪ [00:00, 06:00)，共 600 分）。
func _night_minutes_left() -> float:
	var m := TimeSystem.minute_of_day()
	if m >= float(TimeSystem.NIGHT_START_HOUR) * 60.0:
		return (float(TimeSystem.MINUTES_PER_DAY) - m) \
			+ float(TimeSystem.NIGHT_END_HOUR) * 60.0     # 先到 24:00，再加次日凌晨那 6 小时
	return float(TimeSystem.NIGHT_END_HOUR) * 60.0 - m    # 已在次日凌晨，直到 06:00

## 抱团系数（乘在流失上的倍率）：1.0 = 没人帮，0.2 = 挤满了。
func _huddle_factor() -> float:
	var red := minf(float(_huddle_count) * HUDDLE_PER_NEIGHBOR, HUDDLE_MAX_REDUCTION)
	return 1.0 - red

## 环境有多冷（>1 = 更冷）。**季节系统 / 下雨的接入点**，详见文件头。
## 当前恒 1.0 = "非冬天、不下雨"。
func _cold_multiplier() -> float:
	return 1.0

## 定期重算邻近数。见 `HUDDLE_REFRESH_MIN` 的注释（每帧扫格会吃爆帧预算）。
func _refresh_huddle(dt: float) -> void:
	_refresh_left -= dt
	if _refresh_left > 0.0:
		return
	_refresh_left = HUDDLE_REFRESH_MIN
	var perc := creature.get_component(Perception) as Perception
	_huddle_count = perc.nearby_count(HUDDLE_RADIUS) if perc != null else 0

## 保暖需求的运行时实例。无 Needs / 该物种没挂 warmth → null。
func _warmth() -> Need:
	var needs := creature.get_component(Needs) as Needs
	if needs == null:
		return null
	return needs.need_by_id(WARMTH_ID)
