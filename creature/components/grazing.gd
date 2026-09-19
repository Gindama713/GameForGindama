class_name Grazing
extends CreatureComponent
## 啃食组件：站在可食草格上、按 BITE_INTERVAL 咬一口 → 调 GrassField.bite + Needs.restore("food")。
## 这是「Needs.restore」第一次被真正接上（草案 §7）——吃 = 恢复 food 需求。
##
## 【解耦】不认识 Brain / Body / MapRenderer。只跟两个东西打交道：
##   - GrassField（Autoload 服务）：问草、啃草；
##   - Needs（宿主组件，经 requires 声明硬依赖）：拿饥饿度、恢复 food。
## 往哪走（寻草）由 Brain 用本组件暴露的 hunger_weight / has_nearby_forage / forage_dir 决策，
##   本组件不指挥移动 —— 与「GridMover 只管执行、Brain 只管选向」一致的分工。

const BITE_INTERVAL := 8.0        # 游戏分/口：站在草上每隔多久咬一口 [占位]
const FORAGE_RADIUS := 22         # 找草半径（格）：饿了能感知多远的可食草 [占位]
const FOOD_ID := "food"           # 吃哪一项需求（饱食度）
const WATER_ID := "water"         # 吃草也顺带解一点口渴
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
	# 只吃**嫩草**（耐久未满的新生/再生草）；脚下是满耐久老草就"算了"不吃
	if not GrassField.is_tender(creature.coord):
		return
	var r: Dictionary = GrassField.bite(creature.coord)
	var gained: float = r["food_gained"]
	if gained <= 0.0:
		return
	var needs := creature.get_component(Needs) as Needs
	if needs != null:
		needs.restore(FOOD_ID, gained)                     # 加一些饱食度
		needs.restore(WATER_ID, float(r["water_gained"]))  # 减一点点口渴

# ---------------- 供 Brain 决策用的只读钩子 ----------------

## 饥饿度（0=饱，1=饿极了）：Brain 的 feed 驱动权重 = 该值 × 系数。
func hunger_weight() -> float:
	var f := _food_ratio()
	if f >= SATIETY_STOP:
		return 0.0
	return 1.0 - f

## 附近（FORAGE_RADIUS 内）有没有**嫩草**（没有 → 不产生觅食驱动，猪"算了"）。
func has_nearby_forage() -> bool:
	return GrassField.tender_nearest(creature.coord, FORAGE_RADIUS).x >= 0

## 朝**最嫩**那格草的单位方向（Brain 用它挑一步走的方向）；脚下就是或找不到 → 零向量。
func forage_dir() -> Vector2:
	var here := GrassField.tender_nearest(creature.coord, FORAGE_RADIUS)
	if here.x < 0:
		return Vector2.ZERO
	var delta := Vector2(here - creature.coord)
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
