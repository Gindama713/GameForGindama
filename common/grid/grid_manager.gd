extends Node
## 全局网格管理器（Autoload）。任何代码都能直接引用，方便调试与编写：
##   GridManager.cell_at(0, 0)        -> 取到 (0,0) 这一格
##   GridManager.in_bounds(1, 0)      -> 是否越界
##   GridManager.occupy(c, who)       -> 占格（唯一写入口）
##   GridManager.release(c, who)      -> 释放（唯一写入口）
##   GridManager.random_free_cell()   -> 随机挑一个空格（O(1)，不扫全网格）
##   GridManager.grid.grid_to_world(...) 等坐标换算
##
## 【纪律】Cell.content 是占格的唯一事实来源；`_free` 是它的**派生缓存**，
## 只允许被 occupy()/release() 这两个入口维护 —— 绝不绕过入口直接写 content。

var grid: Grid
var _free: Dictionary = {}   # Vector2i -> true（空格集合，派生缓存）

func _ready():
	grid = Grid.new(40, 24)
	for c in grid.cells.keys():
		_free[c] = true

func cell_at(x: int, y: int) -> Grid.Cell:
	return grid.get_cell(Vector2i(x, y))

func in_bounds(x: int, y: int) -> bool:
	return grid.in_bounds(Vector2i(x, y))

## 占格唯一入口。目标为空、或已经是自己 → 成功；被别人占着 → 拒绝（不静默抢占）。
func occupy(c: Vector2i, who) -> bool:
	var cell := grid.get_cell(c)
	if cell == null:
		return false
	if cell.content != null and cell.content != who:
		return false
	var was: Variant = cell.content
	cell.content = who
	if was == null:
		_free.erase(c)
	return true

## 释放唯一入口。只放自己占的格（防止误清别人的）。
func release(c: Vector2i, who) -> void:
	var cell := grid.get_cell(c)
	if cell == null or cell.content != who:
		return
	cell.content = null
	_free[c] = true

## 随机空格。没有空格返回 Vector2i(-1, -1)（用 x<0 判断）。
func random_free_cell() -> Vector2i:
	if _free.is_empty():
		return Vector2i(-1, -1)
	return _free.keys().pick_random()

## 空格数（调试 / 校验用）
func free_count() -> int:
	return _free.size()

# ---------------- 尸体层（用户拍板 2026-09-19） ----------------
## 尸体**永久留在格上**，但不算占格：活体可以从上面过。
## 移动决策"万不得已"才踩尸体格 —— 那是 GridMover 的规则，这里只存事实。

func place_corpse(c: Vector2i, who) -> void:
	var cell := grid.get_cell(c)
	if cell != null and cell.corpse == null:
		cell.corpse = who

func remove_corpse(c: Vector2i, who) -> void:
	var cell := grid.get_cell(c)
	if cell != null and cell.corpse == who:
		cell.corpse = null

func corpse_at(c: Vector2i):
	var cell := grid.get_cell(c)
	return cell.corpse if cell != null else null
