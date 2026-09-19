class_name CreatureComponent
extends RefCounted

## 组件基类 —— 生物身上「可选的能力 / 需求」。
## Creature 基类只认这套协议，不认具体组件类型。解耦就靠这个：
##   「家的位置」「饿不饿」「会不会制作」都是组件，不是基类字段。
## 需要它的物种自己在 CreatureDef 里声明挂载；不需要的物种身上根本没这个概念。
##
## 【纪律】本文件里的每个钩子都是「通用问题」，答案由各组件自己给。
##   基类只遍历协议、汇总答案，**不许出现任何具体组件的类名**。

var creature: Node = null   # 宿主生物（由 Creature 在装配时注入）

func setup(host: Node) -> void:
	creature = host

## 本组件依赖的其他组件（返回脚本数组）。缺依赖时 Creature 会报错并拒绝装配。
## 例：Brain 依赖 GridMover，就 return [GridMover]。
func requires() -> Array:
	return []

## ---------------- 协议 1：生死 ----------------

## 组件是否判定宿主「已到死境」。
##
## 纪律（取自 CDDA 的 is_dead_state() / die() 分离）：
##   组件只负责**报告事实**，绝不允许自己调 creature.die()。
##   真正的执行由 Creature.check_dead_state() 在每帧 tick 末尾统一接线。
## 于是加一种新死法（饿死 / 中毒 / 暴晒）= 新组件重写本函数，
## 既不改 die()，也不改 tick 循环。
func is_lethal() -> bool:
	return false

## 当 is_lethal() 为真时，用一句话说明死因（写进死亡日志）。
## 与 is_lethal() 配套：基类遍历时取第一个非空的原因。
func lethal_reason() -> String:
	return ""

## ---------------- 协议 2：移动许可 ----------------

## 本组件是否**允许**宿主移动。默认允许。
## 任何会限制移动的组件（断腿、被捆、眩晕、负重超限…）重写本函数返回 false。
## GridMover 只负责「把所有组件的答案与一遍」，不认识任何具体组件。
func allows_movement() -> bool:
	return true

## ---------------- 协议 3：调试表现 ----------------

## 本组件在生成日志里的一段自述（如「血=380/380 部位{…}」）。
## 返回空串 = 这个组件没什么可报的。
## 基类只负责拼接，因此**加一个新组件不必改基类的日志代码**。
func debug_state() -> String:
	return ""

## ---------------- 生命周期 ----------------

## 每帧推进；dt 来自 TimeSystem（已含暂停 / 倍速）。
func tick(_dt: float) -> void:
	pass

func save_data() -> Dictionary:
	return {}

func load_data(_data: Dictionary) -> void:
	pass
