extends Node2D
## 主场景根节点。背景纯黑（project.godot 已设 default_clear_color 黑）。
## 网格逻辑在 GridManager（Autoload），时钟在 TimeSystem（Autoload）。
## 本文件只做两件事：生成生物 / 清空生物 —— 都通过 $Creatures 容器，不散落各处。

const PIG_SCENE := preload("res://creature/pig.tscn")

## 场上所有生物的容器节点（场景树里生物的「区」）。
## 为什么不让生物直接挂 Main：那样它们会和 MapRenderer、UI 平级混着，
## 树里看不出「场上有什么」；清屏也只能靠类型过滤去 Main 的子节点里翻，
## 将来 Main 下多挂一个别的节点就有误伤风险。
## 【绘制顺序】它在 MapRenderer **之后** —— 兄弟节点按顺序绘制、后画的在上层，
## 所以生物画在地表之上。若挪到 MapRenderer 前面，猪会被黑底盖住。
@onready var _creatures: Node2D = $Creatures

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
	_creatures.add_child(pig)
	# 定义校验没过 / 坐标不可用 -> Creature 会拒绝生成（queue_free）。
	# 这时不能把失效引用交出去，否则调用方一碰就 "previously freed"。
	if pig.is_queued_for_deletion():
		return null
	EventBus.creature_spawned.emit(pig)   # 表现层（小地图等）订阅；生成即广播
	return pig

## 调试工具栏「刷猪」用：在随机空格生成一只猪（O(1)，GridManager 维护空格集合）
func spawn_pig_random() -> void:
	var c := GridManager.random_free_cell()
	if c.x < 0:
		print("没有空格可以刷猪了")
		return
	_spawn_pig(c)

## 清空场上所有生物（调试用）。**唯一入口** —— 工具栏不自己遍历节点树，
## 因为「生物装在哪个节点下」是 Main 的知识，不是工具栏的知识。
## 先 emit removed 再 queue_free：表现层（检视面板/小地图）靠事件收尾，不靠 is_instance_valid 兜底。
## 只遍历 _creatures 的子节点，将来 Main 下挂别的节点也不会被误伤。
## 返回移除的数量。
func clear_creatures() -> int:
	var removed := 0
	for c in _creatures.get_children():
		EventBus.creature_removed.emit(c)
		c.queue_free()
		removed += 1
	if removed > 0:
		Log.ev("调试", "清屏：移除 %d 只生物" % removed)
	return removed

## 场上生物数量（调试/自检用）
func creature_count() -> int:
	return _creatures.get_child_count()
