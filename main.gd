extends Node2D
## 主场景根节点。背景纯黑（project.godot 已设 default_clear_color 黑）。
## 网格逻辑在 GridManager（Autoload），时钟在 TimeSystem（Autoload）。
## 本文件只做一件事：在网格上生成一只猪。

const PIG_SCENE := preload("res://creature/pig.tscn")

func _ready() -> void:
	print("=== 网格就绪（逻辑层）===")
	print("尺寸: ", GridManager.grid.width, " x ", GridManager.grid.height, "  格宽: ", Grid.CELL_SIZE)
	print("坐标 (0,0) -> 世界位置 ", GridManager.grid.grid_to_world(Vector2i(0, 0)))
	print("坐标 (1,0) -> 世界位置 ", GridManager.grid.grid_to_world(Vector2i(1, 0)))
	print("坐标 (40,0) 越界? ", not GridManager.in_bounds(40, 0))

	_spawn_pig(Vector2i(20, 12))

func _spawn_pig(at: Vector2i) -> Creature:
	var pig: Creature = PIG_SCENE.instantiate()
	pig.coord = at            # 必须在 add_child 前设好，_ready 才会落对格
	add_child(pig)
	# 定义校验没过 / 坐标不可用 -> Creature 会拒绝生成（queue_free）。
	# 这时不能把失效引用交出去，否则调用方一碰就 "previously freed"。
	if pig.is_queued_for_deletion():
		return null
	EventBus.creature_spawned.emit(pig)   # 表现层（小地图等）订阅；生成即广播
	return pig

## 调试工具栏「刷猪」用：在随机空格生成一只猪
func spawn_pig_random() -> void:
	var free_cells: Array[Vector2i] = []
	for x in GridManager.grid.width:
		for y in GridManager.grid.height:
			var cell := GridManager.cell_at(x, y)
			if cell != null and cell.content == null:
				free_cells.append(Vector2i(x, y))
	if free_cells.is_empty():
		print("没有空格可以刷猪了")
		return
	_spawn_pig(free_cells.pick_random())
