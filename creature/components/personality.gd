class_name Personality
extends CreatureComponent

## 性格组件 —— 个体的「脾气」，出生时由 creature.rng 生成，之后不再变（是稳定特征）。
## 6 维（各 0..1）：攻击性 / 勇气 / 强势性 / 活力 / 焦虑 / 同情心。与《雨世界》官方一致。
##
## 【纪律】
##   1. 性格值 = 个体状态 → 住在这里（组件），不进 Creature 基类。
##   2. 用宿主自己的 rng 生成 → 同一颗世界种子可复现（存档/回放对得上）。
##   3. 本组件不认识任何其他组件：它只「提供数值」，谁来用（Brain）不归它管。
##
## 不写死「猪的类型」——只给 6 个数；行为差异由 Brain 按权重竞争**涌现**出来。

const IDS: Array[String] = ["aggression", "bravery", "dominance", "energy", "nervous", "sympathy"]
## UI 用的单字标签（检视面板 6 格排得下）
const SHORT := {
	"aggression": "攻", "bravery": "勇", "dominance": "强",
	"energy": "活", "nervous": "焦", "sympathy": "同",
}
## 合群度派生权重（占位值，跑出来再调）。见 sociability()。
const SOC_SYMPATHY := 0.5
const SOC_NERVOUS := 0.3
const SOC_CALM := 0.4       # ×(1−攻击性)
const SOC_DOMINANCE := 0.3  # 减项

var values: Dictionary = {}   # id(String) -> float(0..1)

func setup(host: Node) -> void:
	super.setup(host)
	values.clear()
	_generate()

func get_trait(id: String) -> float:
	# 读时叠加"年龄偏移"（幼崽/老年性格不同）；基础基因值见 base_trait
	var ag := creature.get_component(Aging) as Aging
	var shift := ag.trait_shift(id) if ag != null else 0.0
	return clampf(base_trait(id) + shift, 0.0, 1.0)

## 纯基因值（不含年龄偏移）—— 遗传/繁殖用这个，避免把"年龄性格"传给后代。
func base_trait(id: String) -> float:
	return float(values.get(id, 0.5))

## 遗传：性格 = 父母**基因值**均值 ± 小抖动（用宿主 rng，可复现）。让"家族相像"看得见。
## 由繁殖出生时（Main._spawn_offspring）调用，覆盖 setup 的纯随机结果。
func inherit(a: Personality, b: Personality) -> void:
	const JITTER := 0.10
	for id in IDS:
		var va := a.base_trait(id) if a != null else 0.5
		var vb := b.base_trait(id) if b != null else 0.5
		var mean := (va + vb) * 0.5
		values[id] = clampf(mean + creature.rng.randf_range(-JITTER, JITTER), 0.0, 1.0)

## 合群度（派生量，0..1）：越高越爱扎堆，越低越独行。
##   sociability = 同情 + 焦虑 + (1−攻击) − 强势   （各项带占位权重）
## 依据《雨世界》：同情高本就爱群；焦虑高为安全感贴群；攻击高不容人减分；强势高要当头略减。
func sociability() -> float:
	return clampf(
		SOC_SYMPATHY * get_trait("sympathy")
		+ SOC_NERVOUS * get_trait("nervous")
		+ SOC_CALM * (1.0 - get_trait("aggression"))
		- SOC_DOMINANCE * get_trait("dominance"),
		0.0, 1.0)

func debug_state() -> String:
	var parts: Array[String] = []
	for id in IDS:
		parts.append("%s%.2f" % [SHORT[id], get_trait(id)])
	parts.append("合%.2f" % sociability())
	return " ".join(parts)

# ---------------- 生成 ----------------

func _generate() -> void:
	var d: PersonalityDef = null
	if creature.def != null:
		d = creature.def.personality
	if d == null:
		# 没配性格数据 → 全体中性 0.5 并**明确警告**（不静默变成随机噪声）
		push_warning("[%s] 未配置 personality，性格全取中性 0.5" % creature.tag())
		for id in IDS:
			values[id] = 0.5
		return

	var rng: RandomNumberGenerator = creature.rng
	if d.generation_mode == PersonalityDef.GenerationMode.PURE_RANDOM:
		for id in IDS:
			values[id] = _ind(rng, d)
		return

	# 关联公式（**占位**：借鉴《雨世界》「3 个基础值 → 派生 3 维」的思路，系数自拟）。
	# 【关键】独立维以 0.5 为均值；派生维一律用 `(x − 0.5)` 的**偏移量**推导，
	#   于是每个维度的**期望值都是 0.5** ——「平均个体六维都落在 0.5，个体差异是对 0.5 的上下浮动」。
	var bravery := _ind(rng, d)
	var energy := _ind(rng, d)
	var sympathy := _ind(rng, d)
	values["bravery"] = bravery
	values["energy"] = energy
	values["sympathy"] = sympathy
	# 焦虑：越不勇、越不同情 → 越高
	var n_raw := 0.5 - 0.7 * (bravery - 0.5) - 0.5 * (sympathy - 0.5)
	values["nervous"] = _finish(n_raw, d)
	# 攻击：越不同情、越有活力 → 越高
	values["aggression"] = _finish(0.5 - 0.7 * (sympathy - 0.5) + 0.5 * (energy - 0.5), d)
	# 强势：越有活力、越不焦虑 → 越高
	values["dominance"] = _finish(0.5 + 0.8 * (energy - 0.5) - 0.6 * (n_raw - 0.5), d)

## 独立维度：以 0.5 为均值的正态采样 → 归一收尾。
func _ind(rng: RandomNumberGenerator, d: PersonalityDef) -> float:
	return _finish(rng.randfn(0.5, d.spread), d)

## 统一收尾：截断 0..1，再按物种设置推离 0.5。
## push_from_half = 0（默认）时不动 → 值聚在 0.5 附近；调大则把值推向两端（个体更极端）。
func _finish(v: float, d: PersonalityDef) -> float:
	return _push(clampf(v, 0.0, 1.0), d.push_from_half)

## 把值推离 0.5：k=0 不变；k 越大，值越靠两端（中间值少见）。t∈[-1,1] → sign(t)·|t|^(1−k) → 回 [0,1]。
func _push(v: float, k: float) -> float:
	var kk := clampf(k, 0.0, 0.9)
	if kk <= 0.0:
		return v
	var t := (v - 0.5) * 2.0
	return clampf(0.5 + signf(t) * pow(absf(t), 1.0 - kk) * 0.5, 0.0, 1.0)
