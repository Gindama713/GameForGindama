class_name Grid
extends RefCounted

## 逻辑网格：每个 (x,y) 坐标都是一个真实存在的 Cell，可被寻址、可被挂数据。
## 纯数据，不负责渲染——画面黑不黑与它无关。

const CELL_SIZE := 32

var width: int
var height: int
var cells: Dictionary = {}   # key: Vector2i, value: Cell

func _init(p_width := 40, p_height := 24):
	width = p_width
	height = p_height
	# 预先把每一格都造出来，保证 (0,0) (1,0) ... 在代码里真实存在
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			cells[c] = Cell.new(c)

func in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < width and coord.y < height

func has_cell(coord: Vector2i) -> bool:
	return cells.has(coord)

func get_cell(coord: Vector2i) -> Cell:
	return cells.get(coord)

func grid_to_world(coord: Vector2i) -> Vector2:
	return Vector2(coord) * CELL_SIZE

func world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL_SIZE).floor())

# 调试用：遍历所有格执行回调
func for_each_cell(callback: Callable) -> void:
	for cell in cells.values():
		callback.call(cell)

class Cell:
	var coord: Vector2i
	var terrain: StringName = &"unknown"   # 以后放 地形类型（沙/石/草...）
	var content = null                      # 占格者（活体/物品），**唯一**——同格只容一个
	var corpse = null                       # 尸体（不占 content，活体可以从这格过）

	func _init(p_coord: Vector2i):
		coord = p_coord
