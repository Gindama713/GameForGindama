class_name Concealment
extends CreatureComponent

## 隐蔽组件 —— 宿主**所在格的地形**是否把它藏起来（如高草）。
##
## 【无状态】「藏没藏」= 当前格地形的纯函数，不存字段、不需要 tick。
##   地形只在移动时改变，因此基类在 move_to() 成功后重新评估并应用表现（见 Creature._apply_appearance），
##   不必每帧轮询 —— 省掉 100×100 上每只生物的每帧查询。
##
## 【谁消费它】
##   - Creature ：聚合成 is_concealed()，表现层据此决定「画不画」。
##   - Perception：跳过隐蔽中的生物 -> 「藏进草丛就没人看得见」。
##
## 【谁挂它】物种数据 CreatureDef.component_scripts 声明（猪已挂）。

func is_concealed() -> bool:
	var cell := GridManager.cell_at(creature.coord.x, creature.coord.y)
	if cell == null:
		return false
	return Terrain.conceals(cell.terrain)

func debug_state() -> String:
	return "隐蔽=%s" % ("是" if is_concealed() else "否")
