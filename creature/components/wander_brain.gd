class_name WanderBrain
extends CreatureComponent

## 游荡大脑 —— 这只猪「自己的逻辑」。
## 每隔一小段停顿，随机挑一个空方向走一格；没路可走就再等一会。
## 这是最小自主行为。以后想做「饿了→朝食物走」，就换一个 Brain 组件，不碰基类、不碰移动组件。
##
## 【纪律】随机数走宿主自己的 rng（creature.rng），不用全局 randi/randf。
##   这样同一颗世界种子能复现整场模拟，存档/回放才对得上。

var step_interval: float = 0.8      # 两次移动之间的停顿（秒）——占位值，待调
var interval_jitter: float = 0.3    # 停顿随机浮动，避免多只生物同频

var _timer: float = 0.0

func requires() -> Array:
	return [GridMover]              # 无移动组件则无从游荡

func setup(host: Node) -> void:
	super.setup(host)
	_reset_timer()

func tick(dt: float) -> void:
	# 不判断生死 —— 死了就不会被 tick（Creature.die() 已把宿主摘出时钟）
	_timer -= dt
	if _timer > 0.0:
		return
	var mover := creature.get_component(GridMover) as GridMover
	if mover != null:
		var dirs := mover.free_directions()
		if not dirs.is_empty():
			mover.try_step(dirs[creature.rng.randi_range(0, dirs.size() - 1)])
	_reset_timer()

func _reset_timer() -> void:
	_timer = maxf(step_interval + creature.rng.randf_range(-interval_jitter, interval_jitter), 0.05)

## 调试自述（生成日志 + 调试器检查器里的 debug/components/wander_brain 行）
func debug_state() -> String:
	return "下次动作 %.1fs / 间隔 %.1f±%.1f" % [_timer, step_interval, interval_jitter]
