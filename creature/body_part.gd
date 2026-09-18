class_name BodyPart
extends RefCounted

## 部位运行时状态。由 Body 组件从 BodyPartDef 实例化。
## 部位状态是涌现式能力的来源：断肢 -> hp 归零 -> 宿主走不动（经 allows_movement 协议）。

var def: BodyPartDef
var hp: float
var bleeding: float = 0.0     # 每秒掉血；归零时由 Body 主动清零（出血结束）

# 调试日志去重标记（避免每帧刷屏）
var _half_logged: bool = false    # 是否已报过「掉到 50% 以下」
var _down_logged: bool = false    # 是否已报过「失能」

func _init(p_def: BodyPartDef) -> void:
	def = p_def
	hp = p_def.max_hp

## 血量比例。**除零保护**：max_hp 配成 0 时返回 0 而不是 NaN。
## （NaN 会一路流进 UI 的像素条，且不会报错，属于最难查的一类问题。）
func ratio() -> float:
	if def.max_hp <= 0.0:
		return 0.0
	return clampf(hp / def.max_hp, 0.0, 1.0)

func function_ok() -> bool:
	return hp > 0.0

func apply_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)

func add_bleeding(amount: float) -> void:
	bleeding = maxf(bleeding + amount, 0.0)

func status_text() -> String:
	if hp <= 0.0:
		return "失能"
	if bleeding > 0.0:
		return "出血"
	return "正常"
