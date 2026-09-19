class_name GrassDef
extends Resource
## 一种草的静态定义（物种级数据）。加一种草 = 配一份 .tres，不改逻辑。
## 仿 CreatureDef/NeedDef：只放数值 + 外观；具体推进在 GrassField / 运行时状态在 GrassTile。
##
## 机制对齐用户拍板（见 docs/草场放牧系统_实现方案.md）：
##   - "吃几次消失"：max_bites = 成熟耐久，啃一口 −1，归 0 = 秃。
##   - "不吃就长好"：recover_per_bite_min = 每恢复 1 点耐久所需游戏分（持续累计）。
##   - "成熟从周围 9 格扩散"：mature 格每 spread_interval_min 试一次，以 spread_chance 在
##     (2r+1)² 邻域挑一个 plantable、未被占领、当前无草的格定殖 seed_bites 的新格。

@export var display_name: String = "牧草"
@export var texture: Texture2D                 # 成熟贴图（可空 → 用地形色兜底）

# —— 耐久与再生 ——
@export var max_bites: int = 4                 # 成熟耐久（能被啃几次到秃）[占位]
@export var edible_min_bites: int = 1          # 耐久 ≥ 此值才可被啃 / 可扩散
@export var recover_per_bite_min: float = 60.0 # 每 +1 耐久所需游戏分（不被啃时）[占位]
@export var depleted_extra_penalty: float = 1.5 # 归 0 后再生倍慢（伤根效应，>1）[占位]

# —— 扩散 ——
@export var spread_interval_min: float = 120.0 # 成熟格每隔多少分试一次扩散 [占位]
@export var spread_chance: float = 0.20        # 每次尝试成功概率（0..1）[占位]
@export var spread_radius: int = 1             # 邻域半径（1 → 3×3 = 9 格）
@export var seed_bites: int = 1                # 新定殖格起始耐久

# —— 喂养 ——
@export var food_per_bite: float = 5.0         # 啃一口恢复多少 food 需求（饱食度）[占位]
@export var water_per_bite: float = 2.0        # 啃一口恢复多少 water 需求（口渴，"一点点"）[占位]

## 定义校验（空数组 = 通过）。与 CreatureDef.validate() 同构，由 DefValidator 启动期扫描。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if display_name.strip_edges().is_empty():
		errs.append("display_name 为空")
	if max_bites <= 0:
		errs.append("max_bites 必须 > 0（否则草一口就没）")
	if edible_min_bites < 1 or edible_min_bites > max_bites:
		errs.append("edible_min_bites 需落在 [1, max_bites]（当前 %d / max %d）" % [edible_min_bites, max_bites])
	if recover_per_bite_min <= 0.0:
		errs.append("recover_per_bite_min 必须 > 0（否则草瞬回或不回）")
	if depleted_extra_penalty <= 0.0:
		errs.append("depleted_extra_penalty 必须 > 0")
	if spread_interval_min <= 0.0:
		errs.append("spread_interval_min 必须 > 0")
	if spread_chance < 0.0 or spread_chance > 1.0:
		errs.append("spread_chance 需落在 0..1（当前 %.2f）" % spread_chance)
	if spread_radius < 1:
		errs.append("spread_radius 至少 1（否则没有邻域）")
	if seed_bites < 1 or seed_bites > max_bites:
		errs.append("seed_bites 需落在 [1, max_bites]")
	if food_per_bite <= 0.0:
		errs.append("food_per_bite 必须 > 0")
	if water_per_bite < 0.0:
		errs.append("water_per_bite 不能为负（0 = 草不解渴）")
	return errs
