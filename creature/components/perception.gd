class_name Perception
extends CreatureComponent

## 感知组件 —— 扫出半径 R 内的同类邻居 + **威胁** + **任何活体**。
## 现阶段服务于「社交驱动」（合群 / 独行）、「逃命驱动」（flee）与「体温互助」（抱团）；
## 将来「看见捕食者」也走这里。
##
## 【纪律】只**读** GridManager 的占格事实（cell.content），不改任何状态。
## 扫一个 (2R+1)² 方块，靠 cell 直接取 —— 比遍历全网格便宜得多。
##
## 同类判定：`def` 相同（同一个 Resource 引用）。目前只有猪；将来多物种时这就是「只看同种」。
##
## 【威胁判定 —— 2026-09-20 新增，为"动物疾跑逃命"提供触发源】
##   此前本组件**只看得见同物种** —— 于是猪根本不知道玩家在旁边，
##   "让动物更快逃离危险"这条需求没有落点（疾跑给它们也永远不触发）。
##   现在把「**在 `"player"` 组里的生物 + 没藏起来**」算作威胁。
##   ⇒ 顺带让 `Concealment` **第一次有了玩法后果**：藏进高草 -> 猪看不见你 -> 猪不逃。

## 主角的组标。**唯一事实来源在 `common/groups.gd`** ——
## 原先这里、`main.gd`、`ui/creature_inspector.gd` 三处各写一遍 `"player"`，
## 每处的注释还都写着"与 XXX 同一个字面量"（那就是同值复制的自我供认）。现已收敛。
const GROUP_PLAYER := Groups.PLAYER

## 感知半径（格）。占位默认值，待调（方案 §8-Q5）。
var radius: int = 6

## 半径内、活着的同类邻居（不含自己）。
func neighbors() -> Array:
	var out: Array = []
	if creature.def == null:
		return out
	for cr in _scan(effective_radius()):
		if cr.def == creature.def:
			out.append(cr)
	return out

## 半径内的**威胁**（活着的玩家、且没藏起来）。
## 【为什么不做成"所有非同类都算威胁"】现在场上有猪和玩家两种生物，
##   若"非同类 = 威胁"，将来加一只兔子也会互相视为威胁、全场乱跑。
##   显式锚定 `"player"` 组是**当前语义最准**的做法；将来真有食肉动物时，
##   应把这里换成"按 `def` 问捕食关系"，而不是提前抽象成"非同类"。
func threats() -> Array:
	var out: Array = []
	for cr in _scan(effective_radius()):
		if cr.is_in_group(GROUP_PLAYER):
			out.append(cr)
	return out

## 共享扫描：半径内、活着的、**没藏起来**的其他生物（不含自己）。
## 邻居与威胁都从这一份结果里过滤 —— 扫描逻辑只写一遍。
## ⚠ 返回的是 `Array`（无类型），调用方各自按需筛选；两边都只做一次遍历。
func _scan(r: int) -> Array:
	var out: Array = []
	var origin: Vector2i = creature.coord
	var rr := maxi(r, 1)
	for dy in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			if dx == 0 and dy == 0:
				continue
			var c: Vector2i = origin + Vector2i(dx, dy)
			if not GridManager.in_bounds(c.x, c.y):
				continue
			var cell := GridManager.cell_at(c.x, c.y)
			if cell == null:
				continue
			var other = cell.content
			if other == null or other == creature:
				continue
			var cr := other as Creature
			if cr == null or not cr.is_alive():
				continue
			if cr.is_concealed():
				continue          # 藏进高草里的看不见 -> 既不算邻居，也不算威胁
			out.append(cr)
	return out

func count() -> int:
	return neighbors().size()

## 本组件**当前实际**的感知半径 = 基础半径 × 宿主各组件给的感知倍率（协议 9）。
## 例：睡着时 `Sleep` 给 0.35 → 半径 6 变成 2 —— **这就是"睡觉时脆弱"的量化**。
##
## ⚠ **只给"发现别人"类查询用**（`neighbors` / `threats`）。
##   物理邻近类查询（`nearby_count` / `nearby_creatures`）**不用它** ——
##   睡着了也必须能被"身边有东西在动"吵醒，否则永远醒不过来。
func effective_radius() -> int:
	var m: float = creature.sense_multiplier()
	return maxi(int(round(float(radius) * m)), 1)

## 半径内、活着的、**没藏起来的其他生物列表**（**不分物种**）。
## 与 `nearby_count()` 同一份扫描，只是把列表交出去（`Sleep` 要逐个问"你在动吗"）。
## ⚠ 半径用**基础** `radius`，**不乘**感知倍率 —— 见 `effective_radius()` 的注释。
func nearby_creatures(r: int = -1) -> Array:
	return _scan(radius if r < 0 else mini(r, radius))

## 半径内、活着的、**没藏起来的其他生物数**（**不分物种**）。
##
## 【与 neighbors() 的分工 —— 两者不能互相替代】
##   `neighbors()` 按 `def` 过滤 -> 只认同物种，服务「社交 / 繁殖 / 跟妈」；
##   本函数**不按 def 过滤** -> 认"任何一具温血身体"，服务 `Thermal` 的**抱团取暖**。
##   理由：取暖是**物理**的（挨着就暖），不是**社会**的 —— 猪能靠着人取暖，人也能靠着猪取暖。
##   如果这里复用 neighbors()，主角（世界上没有第二个人）就会永远数到 0 → **永远最冷**，
##   而"人也是同理"这条需求就落空了。
##
## 【半径】`r < 0` = 用本组件的感知半径；否则取 `min(r, radius)`。
##   ⚠ **本组件只扫到自己的 `radius` 那么远** —— 传一个更大的 r **不会**扫得更远，
##     所以这里**夹住**而不是假装能办到（静默返回错的数比报错更坏）。
##   `Thermal` 传的是 2（"紧挨着"），而感知半径是 6（"看得见"）—— 两个不同的概念，各有各的值。
##   ⚠⚠ **传 `r > radius` 会静默少算**（2026-09-21 加这段警告）：调用方若把抱团半径调到 8，
##     得到的是"6 格内的数量"，**不会报错、也不会有人发现**。
##     所以这里显式断言一次 —— 调用方真的需要更大的半径时，应当去调 `radius` 本身
##     （那是"感知多远"的定义域），而不是指望本函数越界。
##
## 【成本】复用 `_scan()` 的结果，**没有第二份扫描实现**。代价仍是 O((2R+1)²)，
##   所以调用方要注意频率：`Thermal` 每 5 游戏分才调一次（见其 `HUDDLE_REFRESH_MIN`），
##   而 `Brain` 在决策点调用（0.4~1 秒一次）—— 都远低于每帧。
func nearby_count(r: int = -1) -> int:
	assert(r < 0 or r <= radius,
		"nearby_count(r=%d) 超过了本组件的感知半径 %d —— 本函数扫不了那么远，会静默少算" % [r, radius])
	var lim := radius if r < 0 else mini(r, radius)
	var lim2 := float(lim * lim)
	var me: Vector2i = creature.coord
	var n := 0
	# ⚠ 复用 `nearby_creatures()`，**不写第二份扫描**（口径只留一处）。
	for cr in nearby_creatures(r):
		# ⚠ 显式标类型：列表元素是 Variant，直接 `cr.coord` 会一路是 Variant（坑 7）。
		var c := cr as Creature
		if c != null and Vector2(c.coord - me).length_squared() <= lim2:
			n += 1
	return n

func debug_state() -> String:
	var er := effective_radius()
	var rtxt := "R=%d" % radius if er == radius else "R=%d→%d" % [radius, er]
	return "邻居 %d 威胁 %d (%s)" % [count(), threats().size(), rtxt]
