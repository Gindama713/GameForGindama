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
