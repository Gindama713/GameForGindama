class_name Need
extends RefCounted

## 需求运行时状态。由 Needs 组件从 NeedDef 实例化。

var def: NeedDef
var value: float
var _depleted_logged: bool = false   # 调试日志去重

func _init(p_def: NeedDef) -> void:
	def = p_def
	value = p_def.max_value

## 满足度比例。**除零保护**：max_value 配成 0 时返回 0 而不是 NaN。
func ratio() -> float:
	if def.max_value <= 0.0:
		return 0.0
	return clampf(value / def.max_value, 0.0, 1.0)

func is_depleted() -> bool:
	return value <= 0.0
