class_name LifeDef
extends Resource
## 物种级「一生怎么过」的静态定义（数据驱动）。加物种 = 配一份 .tres，不改逻辑。
## 仿 NeedDef/PersonalityDef：只放数值；运行时状态在 Aging / Lineage 组件。
##
## 覆盖：年龄与连续成长、生命阶段、老死、性别比例、繁殖（冷却/每胎/营养门槛/种群上限）。
## 全部 `[占位]`，跑起来再调（§6.7 数值纪律）。

# —— 年龄与成长 ——
@export var lifespan_min: float = 8640.0      # 自然寿命（游戏分）。到点老死。[占位]=6游戏日
@export var mature_ratio: float = 0.20        # 年龄 ≥ 寿命×此比 = 成年（体型满格、性成熟）
@export var elder_ratio: float = 0.75         # 年龄 ≥ 寿命×此比 = 老年
@export var size_baby: float = 0.25           # 出生体型 = 成年的 1/4（用户明确要"小小的"）
@export var size_elder: float = 0.90          # 老年微缩
@export var variance: float = 0.15            # 寿命个体差异 ±15%（creature.rng 派生，可复现）

# —— 性别 ——
@export var male_ratio: float = 0.5           # 出生为雄的概率

# —— 繁殖 ——
@export var breed_cooldown_min: float = 2400.0  # 每胎间隔（游戏分）≈1.7日 [占位]
@export var litter_min: int = 1               # 每胎最少
@export var litter_max: int = 3               # 每胎最多
@export var breed_food_min: float = 0.6       # 双方 food 比例需 ≥ 才肯生
@export var breed_water_min: float = 0.5      # 双方 water 比例需 ≥ 才肯生
@export var max_population: int = 200         # 种群软上限（防指数爆炸）[占位]

## 定义校验（空数组 = 通过）。由 DefValidator 启动期扫描（res://creature 已含 *.tres）。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if lifespan_min <= 0.0:
		errs.append("lifespan_min 必须 > 0")
	if mature_ratio <= 0.0 or mature_ratio >= 1.0:
		errs.append("mature_ratio 需落在 (0,1)（当前 %.2f）" % mature_ratio)
	if elder_ratio <= mature_ratio or elder_ratio >= 1.0:
		errs.append("elder_ratio 需落在 (mature_ratio,1)（当前 %.2f）" % elder_ratio)
	if size_baby <= 0.0 or size_baby > 1.0:
		errs.append("size_baby 需落在 (0,1]（当前 %.2f）" % size_baby)
	if size_elder <= 0.0 or size_elder > 1.0:
		errs.append("size_elder 需落在 (0,1]（当前 %.2f）" % size_elder)
	if variance < 0.0 or variance > 1.0:
		errs.append("variance 需落在 0..1（当前 %.2f）" % variance)
	if male_ratio < 0.0 or male_ratio > 1.0:
		errs.append("male_ratio 需落在 0..1（当前 %.2f）" % male_ratio)
	if breed_cooldown_min <= 0.0:
		errs.append("breed_cooldown_min 必须 > 0")
	if litter_min < 1 or litter_min > litter_max:
		errs.append("litter 需满足 1 <= litter_min <= litter_max（当前 %d..%d）" % [litter_min, litter_max])
	if breed_food_min < 0.0 or breed_food_min > 1.0:
		errs.append("breed_food_min 需落在 0..1")
	if breed_water_min < 0.0 or breed_water_min > 1.0:
		errs.append("breed_water_min 需落在 0..1")
	if max_population < 1:
		errs.append("max_population 必须 >= 1")
	return errs
