class_name Perception
extends CreatureComponent

## 感知组件 —— 扫出半径 R 内的同类邻居 + **威胁**。
## 现阶段服务于「社交驱动」（合群 / 独行）与「逃命驱动」（flee）；将来「看见捕食者」也走这里。
##
## 【纪律】只**读** GridManager 的占格事实（cell.content），不改任何状态。
## 扫一个 (2R+1)² 方块，靠 cell 直接取 —— 比遍历全网格便宜得多。
##
## 同类判定：`def` 相同（同一个 Resource 引用）。目前只有猪；将来多物种时这就是「只看同种」。
##
## 【威胁判定 —— 2026-09-20 新增，为"动物疾跑逃命"提供触发源】
##   此前本组件**只看得见同物种** —— 于是猪根本不知道玩家在旁边，
##   "让动物更快逃离危险"这条需求没有落点（疾跑给它们也永远不触发）。
##   现在把「**在 `"player"` 组里的生物 + 没藏起来**」算作威胁。
##   ⇒ 顺带让 `Concealment` **第一次有了玩法后果**：藏进高草 -> 猪看不见你 -> 猪不逃。

## 主角的组标。与 `main.GROUP_PLAYER` / `CreatureInspector.GROUP_PLAYER` 同一个字面量。
## 【为什么用组而不是 `is_player` 字段】"谁在扮演玩家"是**编排层的知识**，
##   不该往 Creature 基类塞业务身份（违反「主角严格是一个物种」的纪律）。
##   组是 Godot 原生机制，双方都不必认识对方 —— 这是本项目既定的做法。
const GROUP_PLAYER := "player"

## 感知半径（格）。占位默认值，待调（方案 §8-Q5）。
var radius: int = 6

## 半径内、活着的同类邻居（不含自己）。
func neighbors() -> Array:
	var out: Array = []
	if creature.def == null:
		return out
	for cr in _scan():
		if cr.def == creature.def:
			out.append(cr)
	return out

## 半径内的**威胁**（活着的玩家、且没藏起来）。
## 【为什么不做成"所有非同类都算威胁"】现在场上有猪和玩家两种生物，
##   若"非同类 = 威胁"，将来加一只兔子也会互相视为威胁、全场乱跑。
##   显式锚定 `"player"` 组是**当前语义最准**的做法；将来真有食肉动物时，
##   应把这里换成"按 `def` 问捕食关系"，而不是提前抽象成"非同类"。
func threats() -> Array:
	var out: Array = []
	for cr in _scan():
		if cr.is_in_group(GROUP_PLAYER):
			out.append(cr)
	return out

## 共享扫描：半径内、活着的、**没藏起来**的其他生物（不含自己）。
## 邻居与威胁都从这一份结果里过滤 —— 扫描逻辑只写一遍。
## ⚠ 返回的是 `Array`（无类型），调用方各自按需筛选；两边都只做一次遍历。
func _scan() -> Array:
	var out: Array = []
	var origin: Vector2i = creature.coord
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var c: Vector2i = origin + Vector2i(dx, dy)
			if not GridManager.in_bounds(c.x, c.y):
				continue
			var cell := GridManager.cell_at(c.x, c.y)
			if cell == null:
				continue
			var other = cell.content
			if other == null or other == creature:
				continue
			var cr := other as Creature
			if cr == null or not cr.is_alive():
				continue
			if cr.is_concealed():
				continue          # 藏进高草里的看不见 -> 既不算邻居，也不算威胁
			out.append(cr)
	return out

func count() -> int:
	return neighbors().size()

func debug_state() -> String:
	return "邻居 %d 威胁 %d (R=%d)" % [count(), threats().size(), radius]
