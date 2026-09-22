class_name Drinking
extends CreatureComponent

## 饮水组件：渴了站在岸边连续补水；并给 Brain 暴露"该往哪走"的只读钩子。
##
## 【几何前提 —— 本设计的第一原则】水**不可踩**（`Terrain.walkable(water) == false`），
##   所以生物**永远站不到水格上**。于是：
##     "能喝到" = 与自己 **4 邻接**的格里有水（用户拍板：只认 4 邻，不认斜对角）
##     "去哪喝" = 与水邻接的**可走格**（下称"岸格"）
##   ⚠ 这与 `Grazing`（站在草格**上**）是不同的几何关系，所以**不能照抄它**。
##
## 【与草补水的分工（用户拍板：两者并存）】
##   草每口 +2（可持续 ≈0.02/游戏分）只是**缓冲**；口渴流失 0.07/游戏分 -> 净 −0.05 -> 迟早见底。
##   **草只能延后，本组件负责归零。草的一切数值保持不动。**
##   ⚠ 另一个容易漏的点：`Grazing` 在**不饿**时一点水都不给（`tick()` 开头 `if not wants_food(): return`）
##     -> "吃得很饱 + 很渴"的猪**必须**来岸边。这是既有机制咬合出来的行为，不需要额外规则。
##
## 【解耦】不认识 Brain / GridMover 的实例 / GrassField：
##   - 补水只经 `Needs.restore()` 协议（与"睡觉回疲劳""吃草回饱食度"同一个入口）；
##   - 找水只问 `GridManager`（服务）"某地形的格在哪"，不问水是怎么生成的；
##   - **本组件不指挥移动** —— 只暴露 `water_dir()`，由 Brain 决策（与 Grazing 的分工一致）。
##   - 补水的触发**不读 `Brain.last_drive`**：那会把两个组件绑死；且"路过岸边顺手喝两口"本来就合理。
##
## 【可复现】本组件不用随机数（纯几何 + 需求读取）-> 不扰动个体 RNG 序列。

const THIRST_ID := NeedIds.WATER             # 需求 id（口渴）· 字面量收敛到 NeedIds
const WATER_TERRAIN := Terrain.WATER       # 地形 id。恰好与需求同字，但**语义不同**，别合并
const DIRS: Array[Vector2i] = GridMover.DIRS   # 只认 4 邻（用户拍板；放开 8 邻见方案 §7-B）

const WATER_STOP := 0.95          # 比例 ≥ 此值就停（与 Grazing.SATIETY_STOP 对称）
const DRINK_RATE := 1.5           # 站在岸边每游戏分补多少（≈67 游戏分从 0 补满）
## 觅水驱动权重系数。**已实测调过两轮**：
##   初值 5.0 被轮盘摊薄、"动身太晚"，远景猪赶不到湖边就渴死 -> 提到 8.0；
##   2026-09-20 与 `Brain.FEED_GAIN` 一起提到 10.0 —— 猪的时间账被"一次休息 60~150 游戏分"吃掉六成，
##   驱动不拉开量级就完不成"草场 ↔ 湖"那 70~90 格的通勤（实测：渴死 3/8、饿死 5/8）。
## 10.0 对应：r=0.8 -> 1.58（压过白天游荡/发呆）· r=0.5 -> 4.74 · r=0.47 -> 5.05（夜里也走）·
##   r=0.19 -> 8.0×1.6 = 12.8（危险档，远远压过夜间休息）。
const DRINK_GAIN := 10.0
const THIRST_PANIC := 0.20        # 低于此比例 = 危险档
const DRINK_PANIC_BOOST := 1.6    # 危险档权重再乘它 -> 压过夜间 rest(≈4.05)，避免"睡着渴死"
const WATER_SEARCH_RADIUS := 80   # 觅水半径（格）。查询代价与半径无关，故可给大

func requires() -> Array:
	return [Needs]                # 硬依赖：没有 Needs 就谈不上"补回 water"

func tick(dt: float) -> void:
	# 与 Grazing 同构：自己按条件推进，不依赖 Brain 是否选中了 drink 驱动
	if not wants_water():
		return
	if not at_water():
		return
	var needs := creature.get_component(Needs) as Needs
	if needs != null:
		needs.restore(THIRST_ID, DRINK_RATE * dt)

# ---------------- 供 Brain 决策用的只读钩子 ----------------

## 口渴度（0=够水，1=渴极了）：Brain 的 drink 驱动权重 = 该值换算出来的系数。
## 便宜（只读需求），**可以在每次决策时无条件调用**。
func thirst_weight() -> float:
	var r := _thirst_ratio()
	if r >= WATER_STOP:
		return 0.0
	var w := (WATER_STOP - r) / WATER_STOP * DRINK_GAIN
	if r < THIRST_PANIC:
		w *= DRINK_PANIC_BOOST     # 渴到危险：压过夜里睡觉的权重（否则可能出现"睡着渴死"）
	return w

## 自己是否已经在岸边（4 邻格里有水）。便宜（只看 4 格）。
func at_water() -> bool:
	for d in DIRS:
		var c: Vector2i = creature.coord + d
		if not GridManager.in_bounds(c.x, c.y):
			continue
		var cell := GridManager.cell_at(c.x, c.y)
		if cell != null and cell.terrain == WATER_TERRAIN:
			return true
	return false

## 朝最近的**岸格**的单位方向；找不到 / 已经站在岸上 -> 零向量。
## ⚠ 贵（要遍历水格表）-> **只在 Brain 真的选中 drink 时才算**，别无脑放 tick 里。
func water_dir() -> Vector2:
	var bank := _nearest_bank()
	if bank.x < 0:
		return Vector2.ZERO
	var me: Vector2i = creature.coord
	var delta := Vector2(bank - me)
	if delta.length_squared() < 0.0001:
		return Vector2.ZERO      # 脚下就是岸格 -> 站着喝，别原地打转
	return delta.normalized()

func debug_state() -> String:
	return "口渴%.2f %s" % [_thirst_ratio(), "岸边" if at_water() else "离水"]

# ---------------- 内部 ----------------

func wants_water() -> bool:
	return _thirst_ratio() < WATER_STOP

func _thirst_ratio() -> float:
	var needs := creature.get_component(Needs) as Needs
	if needs == null:
		return 1.0
	var nd := needs.need_by_id(THIRST_ID)
	if nd == null:
		return 1.0
	return nd.ratio()

## 半径内离自己最近的"岸格"：**水格的 4 邻邻居中可走的那一格**。找不到 -> (-1,-1)。
##
## 【为什么目标必须是岸格、不能是水格】水不可踩，朝水格走的最后一步必然被
##   `GridMover.is_cell_free()` 拒绝 -> 生物会卡在离水一格处反复"想进去又进不去"（原地抖动）。
##   岸格本身可走，走近之后 `at_water()` 自然为真、自动切到"站着喝"。
##
## 【为什么不预先过滤"这格空不空"】占格是**每帧都在变的动态事实**，预先算成死数据没意义；
##   走不过去就下一帧重算（与 Brain"退化游荡、下次再试"的容错风格一致）。
func _nearest_bank() -> Vector2i:
	var me: Vector2i = creature.coord
	var r2 := WATER_SEARCH_RADIUS * WATER_SEARCH_RADIUS
	var best_any := Vector2i(-1, -1)
	var best_any_d := r2 + 1
	var best_free := Vector2i(-1, -1)          # 优先挑"现在没人站"的岸格
	var best_free_d := r2 + 1
	for v in GridManager.terrain_cells(WATER_TERRAIN):
		var w := Vector2i(v)
		for d in DIRS:
			var c: Vector2i = w + d
			var dx := c.x - me.x
			var dy := c.y - me.y
			var dist := dx * dx + dy * dy
			if dist >= best_any_d and dist >= best_free_d:
				continue                     # 比两个已知最优都远（或超半径）-> 连地形都不用查
			if not GridManager.in_bounds(c.x, c.y):
				continue
			var cell := GridManager.cell_at(c.x, c.y)
			if cell == null or not Terrain.walkable(cell.terrain):
				continue
			if dist < best_any_d:
				best_any_d = dist
				best_any = c
			# 【为什么优先挑空格】只按"几何最近"挑岸格时，若最近那格正被别的猪站着，
			#   本猪永远走不进去 -> 每次决策都朝同一格撞、原地打转（实测渴死就是这么来的）。
			#   被占的格下一帧可能空出来，所以只是"优先"，不是硬性要求。
			if (cell.content == null or cell.content == creature) and dist < best_free_d:
				best_free_d = dist
				best_free = c
	return best_free if best_free.x >= 0 else best_any
