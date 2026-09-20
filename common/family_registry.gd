extends Node
## 家族注册表（Autoload）—— 全局 `id → 活体 Creature` 映射 + 种群计数。
##
## 为什么需要：Lineage 只存 int id（父母/子女），要解析成活体得有个全局表；
##   组件之间不互相持有引用（§6.5 解耦），统一来这里查。
## 生命周期：Creature._ready 注册自己、NOTIFICATION_PREDELETE 注销 → 死/清屏自动摘除，
##   于是"已故亲人"解析为 null（族谱显示已故），不会野指针。
## 保持薄：只做登记/查询/计数，不碰任何业务规则。

var _by_id: Dictionary = {}    # int -> Creature（活体）
# int -> Dictionary（已故快照：sex/mother_id/father_id/children_ids/tag），族谱显示"已故"用
var _archive: Dictionary = {}

func register(c: Node) -> void:
	if c == null:
		return
	_by_id[c.id] = c

## 死/清屏前留一份快照 → 族谱里仍能画出这位（标"已故"），而不是凭空消失。
## **含贴图与配色**（2026-09-20 加）：族谱头像按"这位生前长什么样"画，
## 没有这两个字段的话已故主角/新物种会被画成猪（旧版的 bug）。
func unregister(c: Node) -> void:
	if c == null:
		return
	var cr := c as Creature
	if cr != null:
		var lin: Lineage = cr.get_component(Lineage) as Lineage
		# ⚠ `cr.def` 是 Variant（`Creature.def` 是导出成员）→ 必须显式标类型，
		#   否则 `:=` 推不出（事实文档 §2.4 坑 7，本项目反复踩到的那条）。
		var d: CreatureDef = cr.def
		_archive[cr.id] = {
			"sex": (lin.sex if lin != null else Lineage.Sex.MALE),
			"mother_id": (lin.mother_id if lin != null else -1),
			"father_id": (lin.father_id if lin != null else -1),
			"children_ids": (lin.children_ids.duplicate() if lin != null else []),
			"tag": cr.tag(),
			"texture": (d.texture if d != null else null),
			"color": (d.map_color if d != null else Color(1, 1, 1)),
		}
	_by_id.erase(cr.id if cr != null else -1)

## 按 id 取活体；不存在/已故 → null。
func get_creature(id: int) -> Creature:
	if id < 0:
		return null
	var c = _by_id.get(id)
	return c as Creature

## 按 id 取已故快照（Dictionary）；没有 → 空字典。
func get_record(id: int) -> Dictionary:
	if id < 0:
		return {}
	var r = _archive.get(id)
	return r if r is Dictionary else {}

## 这位是否"存在过"（活体或已故）—— 族谱判断"要不要画这个节点"用。
func knows(id: int) -> bool:
	return _by_id.has(id) or _archive.has(id)

## 当前活体总数（繁殖软上限用）。
func living_count() -> int:
	return _by_id.size()

func debug_state() -> String:
	return "在册 %d" % _by_id.size()
