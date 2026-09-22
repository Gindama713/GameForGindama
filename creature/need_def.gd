class_name NeedDef
extends Resource

## 需求静态定义（数据）。放进 CreatureDef.active_needs，由 Needs 组件实例化。
## 哪些需求被激活是物种级决定（鱼不需要口渴、冷血动物体温规则不同）——全在数据里。

@export var id: String = ""            # 唯一标识，如 "food"
@export var label: String = "需求"     # 中文显示名
@export var max_value: float = 100.0
@export var drain_rate: float = 1.0    # 每秒衰减（占位值，待调）

## 见底即死境：本需求耗尽时，宿主被判定为死亡（由 Needs.is_lethal() 上报，
## Creature 统一执行）。饥饿 / 口渴 / 御寒这类是致命的；疲劳不是（它应该带来减速，而非死亡）。
##
## 说明：这是「见底有后果」的最小实现 —— 直接判死。
## 将来要改成渐进掉血时，只需把这里换成「每秒扣血」类的数据，架构不用动。
@export var depleted_is_lethal: bool = false

## 定义校验（空数组 = 通过）。由 `DefValidator` 启动期扫描时调用。
## 【为什么校验在自己身上】见 `body_part_def.gd` 里同一段注释 ——
##   集中式校验器要逐个点名 Def 类，那是底层反向依赖上层；放在这里校验器只需鸭子类型。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if id.strip_edges().is_empty():
		errs.append("需求缺 id")
	elif not NeedIds.ALL.has(id):
		# 与 `NeedIds.ALL` 对账（§6.10「配错了要立刻喊出来」）。
		# 【为什么值得一条】漏改任一侧 ⇒ `Needs.need_by_id()` 返回 null ⇒ 而每个调用点都有
		#   `if n == null: return` 的兜底（那本身是好习惯）⇒ **不报错、不崩溃，
		#   只是那个机制悄悄不工作**（例：只改 sprint 那处常量 ⇒ 疾跑永不消耗体力，零日志）。
		#   这类错运行期完全看不出来，只能在启动期拦下 —— 而且**两个方向都拦**：
		#   改 `.tres` 漏改常量、改常量漏改 `.tres`，都会在这里命中。
		errs.append("需求 id「%s」不在 NeedIds.ALL 里 —— 请同步 creature/need_ids.gd（当前表：%s）" % [
			id, ", ".join(NeedIds.ALL)])
	if max_value <= 0.0:
		errs.append("需求 %s 的 max_value 必须 > 0（当前 %.1f）" % [id, max_value])
	if drain_rate < 0.0:
		errs.append("需求 %s 的 drain_rate 不能为负（当前 %.1f）" % [id, drain_rate])
	return errs
