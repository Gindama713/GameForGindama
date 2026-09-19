class_name Lineage
extends CreatureComponent
## 亲缘组件：性别（公/母）+ 家族链（mother_id / father_id / children_ids）。
##
## 【为什么不进基类】性别/亲缘是"部分生物才有"的属性（§6.1 反例：别给每条鱼塞 mother_id）。
## 【引用用 id 不用对象】只存 int id（Creature.id 全局自增，已存在）；活体经 FamilyRegistry 解析，
##   父母死了 registry 摘除 → mother()/father() 返回 null（族谱显示"已故"），children_ids 仍留作谱系。
## 【儿子女儿】sons()/daughters() = children 再按对方 sex 分。

enum Sex { MALE, FEMALE }

var sex: Sex = Sex.MALE
var mother_id: int = -1
var father_id: int = -1
var children_ids: Array[int] = []

func setup(host: Node) -> void:
	super.setup(host)
	# 出生性别：按物种 male_ratio + 宿主 rng（可复现）。繁殖出生时 Main 会覆写。
	var life: LifeDef = creature.def.life if (creature != null and creature.def != null) else null
	var male_p := life.male_ratio if life != null else 0.5
	sex = Sex.MALE if creature.rng.randf() < male_p else Sex.FEMALE

func is_male() -> bool:
	return sex == Sex.MALE

func is_female() -> bool:
	return sex == Sex.FEMALE

func sex_text() -> String:
	return "公" if is_male() else "母"

# ---------------- 亲缘解析（经 FamilyRegistry） ----------------

func mother() -> Creature:
	return FamilyRegistry.get_creature(mother_id)

func father() -> Creature:
	return FamilyRegistry.get_creature(father_id)

func children() -> Array:
	var out: Array = []
	for cid in children_ids:
		var c := FamilyRegistry.get_creature(cid)
		if c != null:
			out.append(c)
	return out

func sons() -> Array:
	return _children_of_sex(Sex.MALE)

func daughters() -> Array:
	return _children_of_sex(Sex.FEMALE)

## 配偶 = 我任一活着的子女的另一位亲代（近似；MVP 不做婚姻登记）。无则 null。
func mate() -> Creature:
	for cid in children_ids:
		var kid := FamilyRegistry.get_creature(cid)
		if kid == null:
			continue
		var kl: Lineage = kid.get_component(Lineage) as Lineage
		if kl == null:
			continue
		var other_id := kl.father_id if is_female() else kl.mother_id
		if other_id >= 0 and other_id != creature.id:
			var m := FamilyRegistry.get_creature(other_id)
			if m != null:
				return m
	return null

func set_parents(m_id: int, f_id: int) -> void:
	mother_id = m_id
	father_id = f_id

func add_child_id(cid: int) -> void:
	if not children_ids.has(cid):
		children_ids.append(cid)

func debug_state() -> String:
	return "%s 母#%d 父#%d 子女%d" % [sex_text(), mother_id, father_id, children_ids.size()]

# ---------------- 内部 ----------------

func _children_of_sex(s: Sex) -> Array:
	var out: Array = []
	for c in children():
		var cl: Lineage = (c as Creature).get_component(Lineage) as Lineage
		if cl != null and cl.sex == s:
			out.append(c)
	return out
