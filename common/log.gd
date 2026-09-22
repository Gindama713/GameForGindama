extends Node

## 调试日志统一出口（Autoload）。带「游戏时间戳 + 分类过滤」。
##
## 【用法】分类名**一律用本文件的 `CAT_*` 常量**，不要自己写中文字面量：
##     Log.ev(Log.CAT_SPAWN, "猪#1 ...")
##
## 【为什么必须常量化 —— 这里真出过事】分类名此前在 **20 个调用点**各写一遍中文字面量，
##   而 `categories` 字典里只有 **7 个键**：`生成/受伤/失血/死亡/需求/移动/调试`。
##   ⇒ **`"睡眠"`（6 处）与 `"疾跑"`（2 处）根本不在字典里**。而旧代码是
##     `categories.get(category, true)` —— **默认值是 `true`**，后果有两个：
##       ① 它们永远是「开」，关不掉；
##       ② `Log.set_category("睡眠", false)` 也关不掉（它把键写进字典，可那 8 处调用点
##          早就在用"默认放行"了 —— 换句话说**过滤这个功能对它们形同虚设**）。
##     不崩溃、不报错，只是**日志过滤静默失效**。
##
## 【现在的规矩】
##   1. 分类名只有 `CAT_*` 一处事实来源；`ALL_CATEGORIES` 与 `categories` **双向对账**（`_ready()`）。
##   2. 未知分类 **`push_warning` + 丢弃**（不再"默认放行"）—— 拼错立刻可见。
##   3. `set_category()` **不再凭空新增键**（那正是当年那个坑的入口）。
##
## 【分类默认开关】生成/受伤/失血/死亡/需求/调试/睡眠/疾跑 = 开；
##   移动 = 关（刷屏，需要时 `Log.set_category(Log.CAT_MOVE, true)`）。

# ---------------- 分类名（唯一事实来源）----------------

const CAT_SPAWN := "生成"
const CAT_HURT := "受伤"
const CAT_BLEED := "失血"
const CAT_DEATH := "死亡"
const CAT_NEED := "需求"
const CAT_MOVE := "移动"
const CAT_DEBUG := "调试"
const CAT_SLEEP := "睡眠"
const CAT_SPRINT := "疾跑"

## 全部分类。`categories` 的键集必须与它**完全一致**（`_ready()` 里对账）。
const ALL_CATEGORIES: Array[String] = [
	CAT_SPAWN, CAT_HURT, CAT_BLEED, CAT_DEATH, CAT_NEED, CAT_MOVE, CAT_DEBUG, CAT_SLEEP, CAT_SPRINT,
]

var enabled := true

var categories := {
	CAT_SPAWN: true,
	CAT_HURT: true,
	CAT_BLEED: true,
	CAT_DEATH: true,
	CAT_NEED: true,
	CAT_MOVE: false,
	CAT_DEBUG: true,
	CAT_SLEEP: true,    # 2026-09-22 补登记：原先只出现在调用点、不在字典里（永远开、关不掉）
	CAT_SPRINT: true,   # 同上
}

func _ready() -> void:
	# 双向对账：常量集 ↔ 字典键集。这类"少登记一个键"的错**在运行期完全看不出来**
	# （旧代码默认放行），只能靠启动期对账抓 —— §6.10「配错了要立刻喊出来」。
	for c in ALL_CATEGORIES:
		if not categories.has(c):
			push_error("[日志] 分类常量「%s」没有登记进 categories —— 该分类无法被过滤" % c)
	for k in categories.keys():
		if not ALL_CATEGORIES.has(k):
			push_error("[日志] categories 里的「%s」没有对应的 CAT_ 常量" % k)

func ev(category: String, msg: String) -> void:
	if not enabled:
		return
	if not categories.has(category):
		# 不静默放行：拼错的分类名必须立刻可见（原先默认 true ⇒ 多出一个"默认开、关不掉"的分类）。
		push_warning("[日志] 未知分类「%s」（请用 Log.CAT_* 常量）—— 本条已丢弃：%s" % [category, msg])
		return
	if not categories[category]:
		return
	print("[t=%5.1f][%s] %s" % [TimeSystem.elapsed, category, msg])

func set_category(category: String, on: bool) -> void:
	if not categories.has(category):
		push_warning("[日志] 未知分类「%s」（请用 Log.CAT_* 常量）—— 未做任何修改" % category)
		return
	categories[category] = on

func toggle(category: String) -> void:
	if not categories.has(category):
		push_warning("[日志] 未知分类「%s」（请用 Log.CAT_* 常量）—— 未做任何修改" % category)
		return
	categories[category] = not categories[category]
