extends Node

## 启动期定义校验（Autoload）。
## 扫描 res://creature 下所有 .tres 定义，逐个校验并**报错**。
##
## 这是 CDDA「四阶段加载 → check_all」的最小落地：在继续堆数据之前，
## 先把「配错了会立刻喊出来」建起来。否则数据错了只有两个结局 ——
## 要么运行期静默罢工，要么靠人肉盯着屏幕猜（也就是幻觉式排错）。
##
## 与运行期校验的分工：
##   DefValidator（本文件）—— 启动期扫**全部**定义，连没被生成的物种也查。
##   Creature._ready()     —— 生成时再查一次，校验没通过就直接拒绝生成。

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

func _validate_resource(res: Resource) -> Array[String]:
	if res is CreatureDef:
		return (res as CreatureDef).validate()
	if res is BodyPartDef:
		return _validate_part(res as BodyPartDef)
	if res is NeedDef:
		return _validate_need(res as NeedDef)
	if res is PersonalityDef:
		return _validate_personality(res as PersonalityDef)
	if res is GrassDef:
		return (res as GrassDef).validate()
	if res is LifeDef:
		return (res as LifeDef).validate()
	if res is LakeDef:
		return (res as LakeDef).validate()
	if res is GrasslandDef:
		return (res as GrasslandDef).validate()
	return []

func _validate_part(p: BodyPartDef) -> Array[String]:
	var errs: Array[String] = []
	if p.id.strip_edges().is_empty():
		errs.append("部位缺 id")
	if p.max_hp <= 0.0:
		errs.append("部位 %s 的 max_hp 必须 > 0（当前 %.1f）" % [p.id, p.max_hp])
	return errs

func _validate_need(n: NeedDef) -> Array[String]:
	var errs: Array[String] = []
	if n.id.strip_edges().is_empty():
		errs.append("需求缺 id")
	if n.max_value <= 0.0:
		errs.append("需求 %s 的 max_value 必须 > 0（当前 %.1f）" % [n.id, n.max_value])
	if n.drain_rate < 0.0:
		errs.append("需求 %s 的 drain_rate 不能为负（当前 %.1f）" % [n.id, n.drain_rate])
	return errs

func _validate_personality(p: PersonalityDef) -> Array[String]:
	var errs: Array[String] = []
	if p.spread < 0.0:
		errs.append("性格分布 spread 不能为负（当前 %.2f）" % p.spread)
	if p.push_from_half < 0.0 or p.push_from_half > 1.0:
		errs.append("性格分布 push_from_half 需在 0..1（当前 %.2f）" % p.push_from_half)
	return errs

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
