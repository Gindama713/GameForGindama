class_name Perception
extends CreatureComponent

## 感知组件 —— 扫出半径 R 内的同类邻居。
## 现阶段服务于「社交驱动」（合群 / 独行）；将来「看见捕食者」也走这里。
##
## 【纪律】只**读** GridManager 的占格事实（cell.content），不改任何状态。
## 扫一个 (2R+1)² 方块，靠 cell 直接取 —— 比遍历全网格便宜得多。
##
## 同类判定：`def` 相同（同一个 Resource 引用）。目前只有猪；将来多物种时这就是「只看同种」。

## 感知半径（格）。占位默认值，待调（方案 §8-Q5）。
var radius: int = 6

## 半径内、活着的同类邻居（不含自己）。
func neighbors() -> Array:
	var out: Array = []
	if creature.def == null:
		return out
	var origin: Vector2i = creature.coord
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var c: Vector2i = origin + Vector2i(dx, dy)
			if not GridManager.in_bounds(c.x, c.y):
				continue
			var cell := GridManager.cell_at(c.x, c.y)
			if cell == null:
				continue
			var other = cell.content
			if other == null or other == creature:
				continue
			var cr := other as Creature
			if cr == null or not cr.is_alive():
				continue
			if cr.def == creature.def:
				out.append(cr)
	return out

func count() -> int:
	return neighbors().size()

func debug_state() -> String:
	return "邻居 %d (R=%d)" % [count(), radius]
