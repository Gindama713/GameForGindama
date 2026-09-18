class_name MapRenderer
extends Node2D

## 地图渲染层 —— 把逻辑网格画成 DF 式色块地图。
## 【纪律】只读不写：terrain/content 怎么变是逻辑层的事，这里只画。
##
## 颜色约定（用户拍板）：
##   黑 = 陆地（未细分的地面）   白 = 生物（生物自己的 _draw 画，不归这里）
## 将来 terrain 有了类型（沙/石/草…），往 TERRAIN_COLORS 加一行即可，不改代码。

## terrain 名 -> 颜色。查不到的一律按黑画（含初始值 &"unknown"）。
const TERRAIN_COLORS := {
	&"unknown": Color(0.0, 0.0, 0.0),
}
## 不画网格线（用户拍板 2026-09-19）：画面上只有内容物（生物），格子边界不画。
## 将来要"DF 式格线"就放开下面这段 —— 但那属于装饰，现阶段不做。

func _draw() -> void:
	var g := GridManager.grid
	var s := Grid.CELL_SIZE
	for y in g.height:
		for x in g.width:
			var cell := g.get_cell(Vector2i(x, y))
			var col: Color = TERRAIN_COLORS.get(cell.terrain, Color.BLACK)
			draw_rect(Rect2(Vector2(x, y) * s, Vector2(s, s)), col)
	# 注：现在 terrain 恒为 unknown -> 全黑，与清屏色一致，所以这层暂时"看不见"。
	# 等地形系统写入 terrain 后，同一套色表立刻出效果，不需要改代码。
