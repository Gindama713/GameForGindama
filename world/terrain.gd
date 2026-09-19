class_name Terrain
extends RefCounted

## 地形类型注册表 —— 地形的**唯一事实来源**：id -> {label, texture, color, walkable, conceals, plantable}。
##
## 【纪律】加一种地形 = 加一行数据，逻辑代码一行不改。
##   MapRenderer 取贴图/颜色、GridMover 问可否踩、Concealment 问是否藏匿、GrassField 问可否长草，全走这里。
##
## 表现规则与生物一致：**有图用图，无图用 color 兜底**。
##   - `texture`：主画面逐格铺（`world/art/*.png`，512×512，缩到一格 32px）
##   - `color`  ：**只用于小地图烘底图**（2px/格，贴图没意义）与无图兜底
##
## 【为什么不拆成 .tres】现在只有两种地形，属性是"结构性"的（能不能踩 / 藏不藏人），
##   不是"每个地形一堆可调数值"。等真出现草/沙/石/水各带一堆数值时再拆 Resource。

const UNKNOWN := &"unknown"
const GRASS := &"grass"
const TALL_GRASS := &"tall_grass"

const TEX_GRASS := preload("res://world/art/grass.png")
const TEX_TALL_GRASS := preload("res://world/art/high-grass.png")

## id -> 属性。texture 为 null = 无图，画 color 兜底。
const DEFS := {
	UNKNOWN: {
		"label": "未知",
		"texture": null,
		"color": Color(0.0, 0.0, 0.0),
		"walkable": true,
		"conceals": false,
		"plantable": true,
	},
	GRASS: {
		"label": "草原",
		"texture": TEX_GRASS,
		"color": Color(0.26, 0.45, 0.20),
		"walkable": true,
		"conceals": false,
		"plantable": true,
	},
	TALL_GRASS: {
		"label": "高草",
		"texture": TEX_TALL_GRASS,
		"color": Color(0.13, 0.27, 0.11),
		"walkable": true,
		"conceals": true,
		"plantable": true,
	},
}

static func def(id: StringName) -> Dictionary:
	return DEFS.get(id, DEFS[UNKNOWN])

## 主画面用的贴图；null = 没有图，调用方改用 color_of()。
static func texture_of(id: StringName) -> Texture2D:
	var t: Texture2D = def(id)["texture"]
	return t

## 小地图烘底图 / 无图兜底用的颜色。
static func color_of(id: StringName) -> Color:
	var c: Color = def(id)["color"]
	return c

static func walkable(id: StringName) -> bool:
	return def(id)["walkable"]

static func conceals(id: StringName) -> bool:
	return def(id)["conceals"]

## 草能否在此地形定殖/蔓延（GrassField 扩散用）。
static func plantable(id: StringName) -> bool:
	return def(id)["plantable"]

static func label_of(id: StringName) -> String:
	return def(id)["label"]
