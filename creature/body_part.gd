class_name BodyPart
extends RefCounted

## 部位运行时状态。由 Body 组件从 BodyPartDef 实例化。
## 部位状态是涌现式能力的来源：断肢 -> hp 归零 -> 宿主走不动（经 allows_movement 协议）。

var def: BodyPartDef
var hp: float
var bleeding: float = 0.0     # 每秒掉血；归零时由 Body 主动清零（出血结束）

## 伤势分级（2026-09-20 新增）。**表现层与 UI 共用的一把尺子** ——
## 谁要按伤情上色/换文案，都问 severity()，不要各自写一遍阈值。
## 判据只用 hp 比例（`ratio()`），因为出血/失能最终都体现在掉血上；
## 出血是**趋势**（还在掉），颜色由调用方叠加显示，不混进等级。
enum Severity { HEALTHY, LIGHT, MODERATE, SEVERE, DISABLED }

## 分级阈值：血量比例 **≥** 该值即算该档（从高到低判）。
## 四个数往上调 = 更容易受伤；往下调 = 更皮实。改平衡只动这里。
const SEVERITY_LIGHT := 0.85      # < 85% → 轻伤（轻微黄）
const SEVERITY_MODERATE := 0.55   # < 55% → 中度（橙）
const SEVERITY_SEVERE := 0.25     # < 25% → 重伤（红）；=0 → 失能（暗红）

# 调试日志去重标记（避免每帧刷屏）
var _half_logged: bool = false    # 是否已报过「掉到 50% 以下」
var _down_logged: bool = false    # 是否已报过「失能」

func _init(p_def: BodyPartDef) -> void:
	def = p_def
	hp = p_def.max_hp

## 血量比例。**除零保护**：max_hp 配成 0 时返回 0 而不是 NaN。
## （NaN 会一路流进 UI 的像素条，且不会报错，属于最难查的一类问题。）
func ratio() -> float:
	if def.max_hp <= 0.0:
		return 0.0
	return clampf(hp / def.max_hp, 0.0, 1.0)

func function_ok() -> bool:
	return hp > 0.0

## 伤势分级。阈值集中在 `SEVERITY_*` 常量里，加档/改档只动那一处。
## 返回 `Severity` 枚举 —— 调用方（UI 上色 / 表现层）自己决定每一档长什么样。
func severity() -> Severity:
	if hp <= 0.0:
		return Severity.DISABLED
	var r := ratio()
	if r >= SEVERITY_LIGHT:
		return Severity.HEALTHY
	if r >= SEVERITY_MODERATE:
		return Severity.LIGHT
	if r >= SEVERITY_SEVERE:
		return Severity.MODERATE
	return Severity.SEVERE

## 伤势中文名（与 severity() 一一对应，UI 直接用）。
func severity_text() -> String:
	match severity():
		Severity.DISABLED: return "失能"
		Severity.SEVERE:   return "重伤"
		Severity.MODERATE: return "中度"
		Severity.LIGHT:    return "轻伤"
		_:                 return "完好"

func apply_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)

func add_bleeding(amount: float) -> void:
	bleeding = maxf(bleeding + amount, 0.0)

func status_text() -> String:
	if hp <= 0.0:
		return "失能"
	if bleeding > 0.0:
		return "出血"
	return "正常"

# ---- 日志去重标记的访问器（Body 用；也在本类内被读写，消除"声明未使用"警告）----
func half_logged() -> bool:
	return _half_logged

func mark_half_logged() -> void:
	_half_logged = true

func down_logged() -> bool:
	return _down_logged

func mark_down_logged() -> void:
	_down_logged = true
