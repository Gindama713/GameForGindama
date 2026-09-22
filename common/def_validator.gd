extends Node

## 启动期定义校验（Autoload）。
## 扫描 `SCAN_ROOTS` 下所有 `.tres` 定义，逐个校验并**报错**。
##
## 这是 CDDA「四阶段加载 → check_all」的最小落地：在继续堆数据之前，
## 先把「配错了会立刻喊出来」建起来。否则数据错了只有两个结局 ——
## 要么运行期静默罢工，要么靠人肉盯着屏幕猜（也就是幻觉式排错）。
##
## 与运行期校验的分工：
##   DefValidator（本文件）—— 启动期扫**全部**定义，连没被生成的物种也查。
##   Creature._ready()     —— 生成时再查一次，校验没通过就直接拒绝生成。
##
## ══════════════════════════════════════════════════════════════════
## 【2026-09-22 重构】为什么本文件**不点名任何具体 Def 类**
## ══════════════════════════════════════════════════════════════════
##   改之前这里是一串 `if res is CreatureDef: ... elif res is BodyPartDef: ...`，
##   点名了 8 个类（`CreatureDef` / `BodyPartDef` / `NeedDef` / `PersonalityDef` /
##   `GrassDef` / `LifeDef` / `LakeDef` / `GrasslandDef`）。两个问题：
##     ① **反向依赖**：本文件住在 `common/`（底层），却认识 `creature/` 与 `world/`（上层）。
##        于是 `common/` 永远不能当"可复用的底层"用。
##     ② **每加一种 Def 都要回来改它** —— 加物种是"只配数据"的纪律（§6.9）在这里破了个口。
##
##   ⇒ 改成**鸭子类型**：只问 `res.has_method("validate")`，调它，收结果。
##     校验规则归**各 Def 自己**（`BodyPartDef.validate()` 等），本文件只负责
##     「**去哪找**」和「**怎么报**」两件事。
##     代价是零：本项目的 `CreatureDef` / `LifeDef` / `GrassDef` / `GrasslandDef` /
##     `LakeDef` 一直都是自带 `validate()` 的，只是另三个（部位/需求/性格）的规则
##     之前被写在了这里，本轮搬回它们自己身上。
##
##   ⚠ **目录仍然是契约**：`SCAN_ROOTS` 是"定义资源住在哪"的唯一事实来源。
##     这是本文件仅剩的一处对外知识，且它指的是**数据位置**、不是**代码类型**。
##     改目录布局时**必须同步改这里**（这也是它被写在文件顶部的原因）。

const SCAN_ROOTS: Array[String] = ["res://creature", "res://world/grass", "res://world/grassland", "res://world/lake"]

func _ready() -> void:
	validate_all()

## 扫描并校验全部定义。返回问题条数（0 = 全过）。也可被调试工具手动调用。
func validate_all() -> int:
	var paths: Array[String] = []
	for root in SCAN_ROOTS:
		paths.append_array(_collect_tres(root))
	if paths.is_empty():
		# 扫描本身失效时必须喊出来。否则「0 条问题」和「根本没查到东西」长得一模一样，
		# 比不校验更危险 —— 会让人误以为数据已经过关。
		push_error("[定义校验] 在 %s 下没扫到任何 .tres，校验实际没生效，请检查扫描路径" % ", ".join(SCAN_ROOTS))
		return -1

	var problems := 0
	var bad_files := 0
	for path in paths:
		var res: Resource = ResourceLoader.load(path)
		if res == null:
			bad_files += 1
			problems += 1
			push_error("[定义校验] %s：加载失败" % path)
			continue
		var errs := _validate_resource(res)
		if errs.is_empty():
			continue
		bad_files += 1
		for e in errs:
			problems += 1
			push_error("[定义校验] %s：%s" % [path, e])

	if problems == 0:
		print("[定义校验] 通过：扫描 %d 个定义文件，全部无问题" % paths.size())
	else:
		print("[定义校验] 扫描 %d 个定义文件，其中 %d 个有问题（共 %d 条）" % [paths.size(), bad_files, problems])
	return problems

## 鸭子类型校验：**不点名任何具体类**（理由见文件头）。
##
## ⚠ 扫到「没有 `validate()` 的资源」要**报出来**，不能静默跳过：
##   那几个目录下的 `.tres` 约定**全部**是定义资源（都该自带 `validate()`）。
##   出现一个没有的，要么是放错了目录，要么是新 Def 忘了写 `validate()` ——
##   两种都该在启动期就看见，而不是等到运行期数据出错。
func _validate_resource(res: Resource) -> Array[String]:
	if not res.has_method("validate"):
		return ["这个资源没有 validate() —— %s 目录下的 .tres 约定都是定义资源（放错目录？或新 Def 忘了写 validate()？）" % res.get_class()]
	var raw: Variant = res.call("validate")
	if not (raw is Array):
		return ["validate() 的返回值不是 Array（实际 %s）" % type_string(typeof(raw))]
	var out: Array[String] = []
	for e in raw:
		out.append(str(e))
	return out

## 递归收集 .tres 路径
func _collect_tres(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := root.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_collect_tres(full))
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
