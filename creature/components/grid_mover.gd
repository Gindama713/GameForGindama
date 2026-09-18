class_name GridMover
extends CreatureComponent

## 网格移动组件：只负责「能不能移」和「执行移动」。
## 往哪走不归它管 —— 那是大脑组件的事。移动逻辑与决策逻辑就此解耦。
##
## 【纪律】本组件**不认识 Body**。它只问一件事：
##   所有组件的 allows_movement() 都同意吗？
## 于是将来加「被绳索捆住 / 眩晕 / 负重超限」都不需要回来改这里。

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

## 某格能否进入：在界内 + 没被别的生物/东西占（自己除外）。
## **尸体不算占格**（corpse 不在 content 里）—— 活体"能"走进尸体格。
func is_cell_free(c: Vector2i) -> bool:
	if not GridManager.in_bounds(c.x, c.y):
		return false
	var cell := GridManager.cell_at(c.x, c.y)
	if cell == null:
		return false
	return cell.content == null or cell.content == creature

## 当前四周可走的方向（供大脑挑选）。
## 规则（用户拍板 2026-09-19）：**默认不踩尸体格**；只有首选全空（被围死）时，
## 才把尸体格作为"万不得已"的退路放进来。
## 不能移动时返回空数组 —— 与 try_step() 保持一致，免得大脑白挑一次再被拒。
func free_directions() -> Array[Vector2i]:
	var clean: Array[Vector2i] = []     # 又空又没尸体的格（首选）
	var over_corpse: Array[Vector2i] = []   # 只剩尸体可踩（万不得已）
	if not can_move():
		return clean
	for d in DIRS:
		var c: Vector2i = creature.coord + d
		if not is_cell_free(c):
			continue
		if GridManager.corpse_at(c) != null:
			over_corpse.append(d)
		else:
			clean.append(d)
	return clean if not clean.is_empty() else over_corpse

## 尝试朝 offset 方向走一格；成功返回 true。
func try_step(offset: Vector2i) -> bool:
	if not can_move():
		return false
	return creature.move_to(creature.coord + offset)

## 行动前置：问所有组件「允不允许移动」，全票通过才放行。
## 不再判断 alive —— 死掉的生物已被 die() 摘出时钟，移动组件根本不会被调到。
## 也不认识 Body —— 断腿的否决来自 Body.allows_movement()。
func can_move() -> bool:
	for comp in creature.get_components():
		if not comp.allows_movement():
			return false
	return true
