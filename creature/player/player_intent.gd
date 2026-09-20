class_name PlayerIntent
extends RefCounted

## 玩家「想做什么」与「身体允不允许」之间的**干扰层挂点**（v1 直通，什么都不改）。
##
## 【为什么要有这一层】玩家按下的方向是**意图**，不是命令。将来「疼痛夺走控制 / 恐慌乱走 /
##   力竭走不动 / 中毒摇晃」这类**身体与精神对意图的干扰**，全都插在这里，
##   于是既不用改 `PlayerBrain` 主干、也不用碰 `GridMover`（它只管执行）。
##
## 【v1 是直通的】`apply()` 现在什么都不做 —— 意图原样落到 `dir`。
##   这不是"没写完"，而是**接口先立住**：接缝在了，干扰层落地时是"填函数"而不是"改架构"。

## 本次要提交给 GridMover 的最终方向（apply 之后的值才是真正会走的方向）。
var dir: Vector2i = Vector2i.ZERO

## 玩家原始意图（apply 可能改写 dir，这里保留"他本来想怎么走"，供干扰层比较/表现层用）。
var wanted: Vector2i = Vector2i.ZERO

## 提交一个方向意图。由 PlayerBrain 每次要迈步时调用。
func submit(desired: Vector2i) -> void:
	wanted = desired
	dir = desired

## 干扰层挂点：在"意图"与"执行"之间改写 dir。
## v1 直通（不动）。将来在这里插：
##   疼痛/恐慌 → 以一定概率把 dir 换成随机方向（夺走控制）或清空（僵住）
##   力竭     → 概率性丢步（走两步歇一步的体感）
##   中毒     → 在 dir 上叠一个漂移
## 约定：**本函数不直接移动宿主**，只改 `dir`；移动永远由 PlayerBrain 走 GridMover 执行。
func apply(_creature: Node) -> void:
	# v1：直通。什么都不改。
	pass
