extends Node
## 全局时钟（Autoload）。所有生物 / 系统的时间都从它来，不自己读系统时钟。
## 暂停 = 不发 tick；快进 = 每次发更大的 dt，或一帧多发几次。
## 这样「暂停即停、可快进」是白送的（符合模拟游戏需求）。
## 底层依据：_physics_process 固定步长、确定性；Autoload 挂在树根，比主场景先处理。

signal tick(dt: float)

var paused: bool = false
var speed: float = 1.0
var elapsed: float = 0.0   # 游戏内累计时间（秒）——日志时间戳用

func _physics_process(delta: float) -> void:
	if paused:
		return
	var d := delta * speed
	elapsed += d
	tick.emit(d)
