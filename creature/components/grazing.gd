class_name Grazing
extends CreatureComponent
## 啃食组件：站在可食草格上、按 BITE_INTERVAL 咬一口 → 调 GrassField.bite + Needs.restore("food")。
##
## 【吃草口径（2026-09-20 二次修正）】**到嘴就吃；"嫩草优先"只作用在"往哪走"上。**
##   第一版是"嫩草优先；半径内根本没有嫩草时，老草也吃" —— 那条规则埋了个更隐蔽的卡死：
##   只要有**任意一格**再生中的嫩草落在 `FORAGE_RADIUS(100)` 内，猪站在满耐久草上就**拒绝下嘴**、
##   转而去追那格远处的嫩草；实测（种子 20260918）"站在可食草上"占 8.8% 的时间，
##   而真正能开吃的只有 **1.2%** —— 也就是说 **7.6% 的时间在守着能吃的草挨饿**，最后照样饿死。
##   现在：**脚下可食就吃**（`can_eat_here()` 只问 `is_edible`）；
##   "优先挑嫩的"留给**寻的**（`forage_dir()`，且只在近处才值得绕路，见 TENDER_PREFER_RADIUS）。
##   ⇒ 既不守着草饿死，也不会为了远处一口嫩草走断腿。
##
## 【口径唯一 —— 本组件原有一个卡死 bug】"到没到草、能不能吃"以前被**写了两遍**：
##   本组件的 tick() 用 `is_tender`，而 Brain 的分支用 `is_edible` 判"站住吃"。
##   两者不一致 -> 猪站在满耐久格上"站住了但啃不动"，**永久卡死**（实测踩过）。
##   所以现在把它收成一个方法 `can_eat_here()`，**Brain 一律问本组件**，不许自己再判一遍。
##
## 【解耦】不认识 Brain / Body / MapRenderer。只跟两个东西打交道：
##   - GrassField（Autoload 服务）：问草、啃草；
##   - Needs（宿主组件，经 requires 声明硬依赖）：拿饥饿度、恢复 food。
## 往哪走（寻草）由 Brain 用本组件暴露的 hunger_weight / has_nearby_forage / forage_dir 决策，
##   本组件不指挥移动 —— 与「GridMover 只管执行、Brain 只管选向」一致的分工。

const BITE_INTERVAL := 8.0        # 游戏分/口：站在草上每隔多久咬一口 [占位]
## 找草半径（格）：饿了能感知多远的草。
## **已实测调过**：22 太小 —— 猪被"喝水"驱动带到湖边后离草场 80+ 格，根本感知不到草，
##   于是守在湖边**活活饿死**（实测 5/5 全部「饥饿 耗尽」且一口没吃）。
## 提到 100，与 `Drinking.WATER_SEARCH_RADIUS`(80) 保持同一量级（两者是同类概念，量级别拉开）。
## 成本几乎不变：`*_nearest` 遍历的是**草格表**（O(草格数)），与半径无关。
const FORAGE_RADIUS := 100
## "值得为一口嫩草绕多远的路"（格）。超过了就吃脚下/最近的老草 ——
## 否则一株远处的嫩草会把猪从整片草场上拽走（与"守着草饿死"是同一个病的两面）。
## 取 12：和"草原 ↔ 水"那条间隙（`LakeDef.anchor_gap`）同一个量级，绕这点路是划算的。
const TENDER_PREFER_RADIUS := 12
const FOOD_ID := NeedIds.FOOD      # 吃哪一项需求（饱食度）
const WATER_ID := NeedIds.WATER    # 吃草也顺带解一点口渴
const SATIETY_STOP := 0.95        # food 比例 ≥ 此值就停嘴（吃饱不再空啃、护草）

var _bite_timer: float = 0.0

func requires() -> Array:
	return [Needs]                # 硬依赖：没有 Needs 就谈不上"吃回 food"

func setup(host: Node) -> void:
	super.setup(host)
	_bite_timer = BITE_INTERVAL * 0.5   # 起手给点错峰，别所有猪同帧齐咬

func tick(dt: float) -> void:
	_bite_timer -= dt
	if _bite_timer > 0.0:
		return
	_bite_timer = BITE_INTERVAL        # 到点就重置节奏（无论是否咬成，避免饥饿抖动）
	if not wants_food():
		return
	if not can_eat_here():
		return
	var r: Dictionary = GrassField.bite(creature.coord)
	var gained: float = r["food_gained"]
	if gained <= 0.0:
		return
	var needs := creature.get_component(Needs) as Needs
	if needs != null:
		needs.restore(FOOD_ID, gained)                     # 加一些饱食度
		needs.restore(WATER_ID, float(r["water_gained"]))  # 减一点点口渴

# ---------------- "能不能吃"的唯一判断（Brain 也问这里） ----------------

## 脚下这一格值不值得停下来啃。**只要可食就吃** —— "嫩草优先"只作用在寻的上（见 forage_dir）。
## Brain 的 feed 分支必须调本方法，**不要**自己写 `is_tender`/`is_edible` —— 口径写两遍就会打架。
func can_eat_here() -> bool:
	return GrassField.is_edible(creature.coord)

# ---------------- 供 Brain 决策用的只读钩子 ----------------

## 饥饿度（0=饱，1=饿极了）：Brain 的 feed 驱动权重 = 该值 × 系数。
func hunger_weight() -> float:
	var f := _food_ratio()
	if f >= SATIETY_STOP:
		return 0.0
	return 1.0 - f

## 半径内有没有**可吃的草**（嫩草优先；没有嫩草时老草也算）——没有就不产生觅食驱动。
func has_nearby_forage() -> bool:
	return GrassField.edible_nearest(creature.coord, FORAGE_RADIUS).x >= 0

## 朝"最值得去吃"的方向：**近处有嫩草就挑最嫩的**；否则取最近的可食草。
## （Brain 用它挑一步走的方向）；脚下就是目标 / 找不到草 → 零向量。
func forage_dir() -> Vector2:
	var target := GrassField.tender_nearest(creature.coord, TENDER_PREFER_RADIUS)
	if target.x < 0:
		target = GrassField.edible_nearest(creature.coord, FORAGE_RADIUS)
	if target.x < 0:
		return Vector2.ZERO
	var delta := Vector2(target - creature.coord)
	if delta.length_squared() < 0.0001:
		return Vector2.ZERO
	return delta.normalized()

func debug_state() -> String:
	var f := _food_ratio()
	var grass := GrassField.debug_state(creature.coord)
	return "饥饿%.2f 下次啃%.0fs %s" % [1.0 - f, maxf(_bite_timer, 0.0), grass]

# ---------------- 内部 ----------------

func wants_food() -> bool:
	return _food_ratio() < SATIETY_STOP

func _food_ratio() -> float:
	var needs := creature.get_component(Needs) as Needs
	if needs == null:
		return 1.0
	var nd := needs.need_by_id(FOOD_ID)
	if nd == null:
		return 1.0
	return nd.ratio()
