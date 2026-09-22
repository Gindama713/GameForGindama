class_name PersonalityDef
extends Resource

## 性格静态定义（数据）—— 物种级的「脾气分布」。
## 放进 CreatureDef.personality，由 Personality 组件在出生时按此生成 6 个 0..1 的性格值。
##
## 【纪律 / 边界】6 个维度的**含义与关联公式是框架固定的**（与《雨世界》一致，写在 personality.gd）；
##   本资源只描述「这个物种怎么随机」——不同物种可以有不同脾气分布。
##   于是将来「狼比猪更凶」只是换一份 .tres + 加偏移，不改代码。
##
## 注：最初方案想给 6 个维度各建一份 trait_*.tres；实际没建——
##   维度的 id 会被关联公式按名引用，本质是框架常量，拆成 6 个近乎空文件只是提前抽象。
##   等真出现「按维度配不同分布」的需求再拆。物种级差异目前靠下面的参数表达。

enum GenerationMode {
	PURE_RANDOM,   # 各维独立随机
	CORRELATED,    # 由 bravery/energy/sympathy 关联推导其余三维（公式见 personality.gd，另有标注）
}

@export var generation_mode: GenerationMode = GenerationMode.CORRELATED
@export var spread: float = 0.18          # 独立维度的正态离散度 σ（占位值，待调）
@export var push_from_half: float = 0.0   # 0=值聚在 0.5 附近（默认：居中的平均个体）；越大越把值推离 0.5（个体更极端）

## 定义校验（空数组 = 通过）。由 `DefValidator` 启动期扫描时调用。
## 【为什么校验在自己身上】见 `body_part_def.gd` 里同一段注释 ——
##   集中式校验器要逐个点名 Def 类，那是底层反向依赖上层；放在这里校验器只需鸭子类型。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if spread < 0.0:
		errs.append("性格分布 spread 不能为负（当前 %.2f）" % spread)
	if push_from_half < 0.0 or push_from_half > 1.0:
		errs.append("性格分布 push_from_half 需在 0..1（当前 %.2f）" % push_from_half)
	return errs
