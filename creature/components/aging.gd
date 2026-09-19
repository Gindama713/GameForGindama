class_name Aging
extends CreatureComponent
## 年龄组件：涨岁数 → 连续成长（体型 0.25→1.0）→ 生命阶段（幼/成/老）→ 到寿命**老死**。
##
## 【老死走既有扩展点】重写 is_lethal()/lethal_reason()，基类 check_dead_state() 统一接线，
##   die()/tick 循环零改动（事实文档 §5.3/§6.6）。
## 【体型走协议】visual_scale() 供表现层聚合（仿 is_concealed 套路），基类仍不认识 Aging。
## 【可复现】寿命个体差异用 creature.rng（世界种子派生）→ 同种子同猪同寿命。
## 【不繁殖】繁殖在 Reproduction 组件；本组件只管"自己这一条命"。

enum Stage { JUVENILE, ADULT, ELDER }

var age_min: float = 0.0          # 当前年龄（游戏分）
var lifespan_min: float = 0.0     # 个体寿命（setup 时 = def.life.lifespan × rng(1±variance)）

func setup(host: Node) -> void:
	super.setup(host)
	age_min = 0.0
	lifespan_min = _roll_lifespan()

func tick(dt: float) -> void:
	age_min += dt

# ---------------- 阶段 / 成长 ----------------

func stage() -> Stage:
	if lifespan_min <= 0.0:
		return Stage.ADULT
	var r := age_min / lifespan_min
	var life := _life()
	if life == null:
		return Stage.ADULT
	if r < life.mature_ratio:
		return Stage.JUVENILE
	if r < life.elder_ratio:
		return Stage.ADULT
	return Stage.ELDER

## 连续体型比例：出生 size_baby → 成年(1.0) 线性长个；成年后 1.0；老年微缩到 size_elder。
func size_ratio() -> float:
	var life := _life()
	if life == null or lifespan_min <= 0.0:
		return 1.0
	var r := clampf(age_min / lifespan_min, 0.0, 1.0)
	if r < life.mature_ratio:
		# 幼崽期：从 size_baby 线性长到 1.0
		var t := r / life.mature_ratio
		return lerpf(life.size_baby, 1.0, t)
	if r < life.elder_ratio:
		return 1.0
	# 老年：1.0 → size_elder 线性微缩
	var t := (r - life.elder_ratio) / maxf(1.0 - life.elder_ratio, 0.0001)
	return lerpf(1.0, life.size_elder, clampf(t, 0.0, 1.0))

## 表现层协议：精灵缩放倍率（基类聚合各组件 visual_scale）。
func visual_scale() -> float:
	return size_ratio()

## 速度倍率（决策间隔乘数）：幼/老更慢，成年 1.0。Brain 读它。
func speed_factor() -> float:
	match stage():
		Stage.JUVENILE:
			return 1.6
		Stage.ELDER:
			return 1.3
		_:
			return 1.0

## 身体素质（活力/强壮度，0..1+）：幼崽弱、成年巅峰、老年衰。Body 用它算受伤倍率。
func vitality() -> float:
	match stage():
		Stage.JUVENILE:
			return 0.6
		Stage.ELDER:
			return 0.7
		_:
			return 1.0

## 受伤倍率：体弱（幼/老）更易受伤 = 1/vitality。Body.hurt 乘它。
func damage_multiplier() -> float:
	return 1.0 / maxf(vitality(), 0.0001)

## 性格随年龄的偏移（叠加到 Personality 基础值上，读时生效）：
##   幼崽：好动(+energy)、胆小(+nervous)、不凶(-aggression)、不强势(-dominance)、怯(-bravery)
##   老年：迟缓(-energy)、温和(-aggression)、让权(-dominance)、略警觉(+nervous)
##   成年：0（基准）
func trait_shift(id: String) -> float:
	match stage():
		Stage.JUVENILE:
			match id:
				"energy": return 0.15
				"nervous": return 0.10
				"aggression": return -0.10
				"dominance": return -0.15
				"bravery": return -0.10
				_: return 0.0
		Stage.ELDER:
			match id:
				"energy": return -0.20
				"aggression": return -0.10
				"dominance": return -0.10
				"nervous": return 0.05
				_: return 0.0
		_:
			return 0.0

## 是否性成熟（成年且未老到不育）—— Reproduction 用。
func is_fertile_age() -> bool:
	return stage() == Stage.ADULT

# ---------------- 老死（既有死法扩展点） ----------------

func is_lethal() -> bool:
	return lifespan_min > 0.0 and age_min >= lifespan_min

func lethal_reason() -> String:
	return "老死（活了 %.1f 天）" % (age_min / 1440.0)

# ---------------- 调试 ----------------

func debug_state() -> String:
	var names := ["幼", "成", "老"]
	return "年龄%.1f/%.0f天[%s] 体型%.0f%%" % [
		age_min / 1440.0, lifespan_min / 1440.0, names[stage()], size_ratio() * 100.0]

# ---------------- 内部 ----------------

func _life() -> LifeDef:
	if creature == null or creature.def == null:
		return null
	return creature.def.life

## 个体寿命 = 物种基准 × (1 ± variance)，用宿主 rng（可复现）。
func _roll_lifespan() -> float:
	var life := _life()
	if life == null:
		return 0.0
	var v := life.variance
	var k: float = creature.rng.randf_range(1.0 - v, 1.0 + v)
	return life.lifespan_min * k
