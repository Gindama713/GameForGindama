class_name GrassTile
extends RefCounted
## 单格草的运行时状态（个体的「现在还剩多少 / 计时到哪儿」）。由 GrassField 持有并推进。
## 仿 BodyPart/Need：纯逻辑、不进场景树、不渲染。生命周期只在 GrassField 的 tick 里被推进。

var def: GrassDef
var coord: Vector2i
var durability: int            # 当前耐久 0..def.max_bites；归 0 = 被吃秃

var _recover_acc: float = 0.0  # 再生计时累加（游戏分）
var _spread_acc: float = 0.0   # 扩散计时累加（游戏分）

func _init(p_def: GrassDef, p_coord: Vector2i, p_durability: int) -> void:
	def = p_def
	coord = p_coord
	durability = clampi(p_durability, 0, p_def.max_bites)

## 是否满耐久（成熟）：可扩散、可被啃到上限。
func is_mature() -> bool:
	return durability >= def.max_bites

## 是否可被啃：耐久达到可食下限。
func is_edible() -> bool:
	return durability >= def.edible_min_bites

## 耐久比例（除零保护）：表现层着色用。
func ratio() -> float:
	if def.max_bites <= 0:
		return 0.0
	return clampf(float(durability) / float(def.max_bites), 0.0, 1.0)
