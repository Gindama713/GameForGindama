extends Node
## 全局网格管理器（Autoload）。任何代码都能直接引用，方便调试与编写：
##   GridManager.cell_at(0, 0)        -> 取到 (0,0) 这一格
##   GridManager.in_bounds(1, 0)      -> 是否越界
##   GridManager.occupy(c, who)       -> 占格（唯一写入口）
##   GridManager.release(c, who)      -> 释放（唯一写入口）
##   GridManager.random_free_cell()   -> 随机挑一个空格（O(1)，不扫全网格）
##   GridManager.terrain_cells(id)    -> 某个地形的全部格（派生缓存，O(1) 取表）
##   GridManager.grid.grid_to_world(...) 等坐标换算
##
## 【纪律】Cell.content 是占格的唯一事实来源；`_free` 是它的**派生缓存**，
## 只允许被 occupy()/release() 这两个入口维护 —— 绝不绕过入口直接写 content。
## 同理 `_terrain_cells` 是 `Cell.terrain` 的**派生缓存**，只由 rebuild_terrain_index() 维护。

## 网格尺寸的**唯一来源**（Grid 自己不再给默认值，避免两处各写一份尺寸）
## 2026-09-19：40×24 -> **100×100**（草原环境）-> **130×130**。
##   扩到 130 是为了：草原中心改放在「离地图正中半径 50 的圆周」上随机取点后，
##   草块（长半轴 ~11 + 噪声）连中心一起仍能**整个落在图内**（中心到边 = 65 > 50 + 11.5）。
##   130 格 × 32px = 4160×4160 世界像素，仍靠可拖动/缩放相机（world/camera_rig.gd）观察。
const WIDTH := 130
const HEIGHT := 130

var grid: Grid
var _free: Dictionary = {}   # Vector2i -> true（空格集合，派生缓存）

## 地形索引（派生缓存 2）：地形 id -> 该地形的全部格坐标。
## 【为什么要缓存】"最近的某地形格在哪"如果每次按半径扫 O(r²)，生物一多就撑不住。
##   地形只在启动时写一次 -> 建一次索引（O(地形种数 × 格数)，一次性），
##   之后每次查询代价 = **O(该地形的格数)**，**与搜索半径无关** -> 半径可以放心给大。
## 【唯一事实来源仍是 Cell.terrain】本表只是它的派生视图，绝不反向写。
##   ⚠ 地形改了却不发 `terrain_changed` -> 本索引过期。要改地形，就发那个信号。
var _terrain_cells: Dictionary = {}   # StringName -> PackedVector2Array

func _ready() -> void:
	grid = Grid.new(WIDTH, HEIGHT)
	for c in grid.cells.keys():
		_free[c] = true
	rebuild_terrain_index()
	# GridManager 在 Autoload 顺序里排在 EventBus **之前** -> 此刻 EventBus 还没进树，连不上。
	# 延后到本帧末接线，并**补一次重建**：主场景的 _ready 会在接线之前就把地形生成好。
	_link_bus.call_deferred()

func _link_bus() -> void:
	if not EventBus.terrain_changed.is_connected(rebuild_terrain_index):
		EventBus.terrain_changed.connect(rebuild_terrain_index)
	rebuild_terrain_index()

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

# ---------------- 地形索引（派生缓存，2026-09-20） ----------------

## 重建地形索引。构造期自己调一次；此后由 `terrain_changed` 触发。代价 O(地形种数 × 格数)。
##
## 【为什么两趟扫而不是边扫边 append】Packed 数组是**按值传递（写时复制）**的：
##   往 `dict[key]` 里"就地 append"会改到一个临时副本上、丢掉结果（本项目踩过）。
##   两趟扫：先把地形种类收齐，再逐个地形建一个 PackedVector2Array 后**一次性写回** —— 没有中途修改。
func rebuild_terrain_index() -> void:
	var kinds: Dictionary = {}
	for c in grid.cells.keys():
		var cell: Grid.Cell = grid.cells[c]
		if cell == null:
			continue
		kinds[cell.terrain] = true
	var built: Dictionary = {}
	for t in kinds.keys():
		var arr := PackedVector2Array()
		for c in grid.cells.keys():
			var cell: Grid.Cell = grid.cells[c]
			if cell != null and cell.terrain == t:
				arr.append(Vector2(c))
		built[t] = arr
	_terrain_cells = built

## 某个地形的全部格（只读视图；返回的是副本，调用方改不动缓存）。
## 没有这种地形 -> 空数组。查询"最近的某地形格"请自己遍历它 —— 代价 O(格数)。
func terrain_cells(id: StringName) -> PackedVector2Array:
	var arr: PackedVector2Array = _terrain_cells.get(id, PackedVector2Array())
	return arr

## 某个地形有多少格（调试 / 断言用）。
func terrain_cell_count(id: StringName) -> int:
	var arr: PackedVector2Array = _terrain_cells.get(id, PackedVector2Array())
	return arr.size()

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
