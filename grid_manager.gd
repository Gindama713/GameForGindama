extends Node
## 全局网格管理器（Autoload）。任何代码都能直接引用，方便调试与编写：
##   GridManager.cell_at(0, 0)        -> 取到 (0,0) 这一格
##   GridManager.in_bounds(1, 0)      -> 是否越界
##   GridManager.grid.grid_to_world(...) 等坐标换算

var grid: Grid

func _ready():
	grid = Grid.new(40, 24)

func cell_at(x: int, y: int) -> Grid.Cell:
	return grid.get_cell(Vector2i(x, y))

func in_bounds(x: int, y: int) -> bool:
	return grid.in_bounds(Vector2i(x, y))
