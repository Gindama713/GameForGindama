class_name BodyPartDef
extends Resource

## 部位静态定义（数据）。放进 CreatureDef.body_parts，由 Body 组件实例化出运行时状态。
## 加物种 = 配一份部位清单，不碰任何系统代码。
##
## 设计依据（CDDA src/bodypart.h 的 body_part_type）：
##   「是不是要害」「算不算肢体」都是**数据字段**，不是代码里的 category 字符串比较。
##   于是加一个要害部位、加一条腿，都只是配数据，规则代码一行都不动。

@export var id: String = ""            # 唯一标识，如 "head"
@export var label: String = "部位"     # 中文显示名
@export var max_hp: float = 100.0

## 要害：此部位 hp 归零即判宿主死亡（由 Body.is_lethal() 上报，Creature 统一执行）。
@export var is_vital: bool = false

## 该部位承担的肢体职能（集合，可同时属于多种；CDDA 里是带权重的 limbtypes 映射，我们先用集合）。
##   "stance"  支撑/行走 —— 至少一条存活才能移动
##   "grasp"   抓握     —— 预留给「伤臂不能制作」
## 空数组 = 不是肢体。任何部位都不带 "stance" 的物种（鱼/蛇）不受腿伤限制。
@export var limb_types: Array[String] = []

## 仅用于分组与显示（将来「按类别批量选部位」的选择器）。**不参与任何规则判定。**
@export var category: String = "other"

func is_limb() -> bool:
	return not limb_types.is_empty()

func has_limb_type(t: String) -> bool:
	return limb_types.has(t)
