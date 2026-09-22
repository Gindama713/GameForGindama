class_name Reproduction
extends CreatureComponent
## 繁殖组件：可育**母**猪 + 相邻可育**公**猪 + 双方吃饱喝足 + 冷却到 → 发 `EventBus.birth_requested`。
##
## 【只"请求"，不造娃】真 instantiate/add_child 在 Main（生成唯一入口，§3.2/§6.5）。
##   组件不碰场景树、不碰 $Creatures。
## 【只母发起】避免公母双向重复计数同一次交配。
## 【限流防爆炸】冷却 + 营养门槛 + 种群软上限（Main 侧再查一次）三重闸。
## 【先判便宜条件再搜索】性别/年龄/冷却/营养都不满足时直接 return，不做邻域搜索（省性能）。

## 营养门槛查哪两项需求。字面量收敛到 `NeedIds`（唯一事实来源）——
## 原先这里直接写裸字符串 `need_by_id("food")`，是全项目唯一没定义常量的一处（已补齐；2026-09-22 又收敛到 NeedIds）。
const FOOD_ID := NeedIds.FOOD
const WATER_ID := NeedIds.WATER

var _cooldown: float = 0.0

func requires() -> Array:
	return [Aging, Lineage]        # 硬依赖：要年龄(性成熟)与性别

func setup(host: Node) -> void:
	super.setup(host)
	_cooldown = _life().breed_cooldown_min * 0.5 if _life() != null else 0.0

func tick(dt: float) -> void:
	_cooldown -= dt
	if _cooldown > 0.0:
		return
	if not _self_ready():
		return
	var mate := _find_mate()
	if mate == null:
		return
	_cooldown = _life().breed_cooldown_min
	EventBus.birth_requested.emit(creature, mate)

# ---------------- 判定 ----------------

## 自己是否"想生且能生"：母、性成熟、营养够。
func _self_ready() -> bool:
	var lin := creature.get_component(Lineage) as Lineage
	var age := creature.get_component(Aging) as Aging
	if lin == null or age == null:
		return false
	if not lin.is_female():
		return false
	if not age.is_fertile_age():
		return false
	return _nutrition_ok()

## 在感知半径内找一个"可育公猪"邻居。
func _find_mate() -> Creature:
	var perc := creature.get_component(Perception) as Perception
	if perc == null:
		return null
	for n in perc.neighbors():
		var c := n as Creature
		var cl: Lineage = c.get_component(Lineage) as Lineage
		var ca: Aging = c.get_component(Aging) as Aging
		if cl == null or ca == null:
			continue
		if cl.is_male() and ca.is_fertile_age():
			# 对方也要吃饱（双方门槛）
			if _nutrition_ok_for(c):
				return c
	return null

func _nutrition_ok() -> bool:
	return _nutrition_ok_for(creature)

func _nutrition_ok_for(c: Creature) -> bool:
	var life := _life()
	if life == null:
		return true
	var needs := c.get_component(Needs) as Needs
	if needs == null:
		return true
	var f := needs.need_by_id(FOOD_ID)
	var w := needs.need_by_id(WATER_ID)
	if f != null and f.ratio() < life.breed_food_min:
		return false
	if w != null and w.ratio() < life.breed_water_min:
		return false
	return true

func _life() -> LifeDef:
	if creature == null or creature.def == null:
		return null
	return creature.def.life

func debug_state() -> String:
	return "繁殖冷却%.0f分" % maxf(_cooldown, 0.0)
