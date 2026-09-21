extends Node

## 睡眠时间导演（2026-09-21）—— 主角睡觉时把时间加速，醒了立刻恢复。
##
## ══════════════════════════════════════════════════════════════════
## 一、为什么这件事**不能**写在 `Sleep` 组件里
## ══════════════════════════════════════════════════════════════════
##   `TimeSystem.speed` 是**全局**的 —— 它一改，整张地图的生物、草场、需求全都按新倍率走。
##   而"谁睡觉值得让全世界加速"是**编排层的策略**，不是生物自身的属性：
##     · 一只猪睡了，世界当然不该加速；
##     · 只有**主角**睡了才该加速。
##   ⇒ 组件只描述**状态**（`Sleep.is_sleeping()`），**策略**放在这里。
##     这与 `main.gd` 里"谁在扮演玩家由编排层决定"是同一条纪律。
##
## ══════════════════════════════════════════════════════════════════
## 二、为什么必须**加速**而不是"跳过"
## ══════════════════════════════════════════════════════════════════
##   用户 2026-09-21 拍板走"把夜晚当后台"这条路线。关键区别：
##     · **跳过** = 不模拟 —— 那夜里就没有危险了，"睡觉"变成无风险的免费回血；
##     · **加速** = 照常逐帧模拟，只是不逐帧看 —— 危险、寒冷、生育、草生长**全都照常发生**。
##   ⇒ 用户问过"玩家难道就看着角色躺那么久吗"。答案是：**夜里其实没东西可看**
##     （实测猪在夜里 93% 的时间在睡，画面几乎静止）。所以加速 + 醒来给反馈，
##     既解决了"干等"，又没有把风险抹掉。
##
##   ⚠ 倍率上限的物理依据：`TimeSystem.tick` 走 `_physics_process`（默认 60Hz），
##     所以 `speed = 60` 时 dt = 1 游戏分/物理帧 —— 再往上画面就开始"跳格"了。
##     取 30：一夜（20:00→06:00 = 600 游戏分）= **20 真实秒**，仍在舒适区间。
##
## ══════════════════════════════════════════════════════════════════
## 三、它怎么知道"主角是谁"
## ══════════════════════════════════════════════════════════════════
##   订阅 `EventBus.player_spawned` —— 与 `PlayerHud` / `CameraRig` 同一套路，
##   于是 `main.gd` 不必记得"生成主角后还要喂这里一口"（少一处接线疏漏）。
##   主角死了 / 被清屏了 -> `is_instance_valid` 为假 -> 立刻恢复正常倍率。
##   ⚠ 这一条**必须有**：主角睡着时死亡，`Creature.die()` 会把它从时钟上摘下来，
##     于是 `Sleep` 再也不会 tick、状态**永远停在 ASLEEP** —— 不判有效性的话
##     整个世界会以 30 倍速永远转下去。

## 主角睡着时的时间倍率。见文件头第二节。
const SLEEP_SPEED := 30.0
## 正常倍率。
const NORMAL_SPEED := 1.0

var _player: Creature = null
var _sleep: Sleep = null
## 上一次真正写进 `TimeSystem.speed` 的值。只在**变化时**写，
## 免得每帧都去碰一个全局单例（也免得将来别人改了倍率又被本节点按回去）。
var _applied := NORMAL_SPEED

func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	# 场景里可能已经有主角了（本节点若排在 Main 之后 _ready）—— 兜一次底。
	var m := get_parent()
	if m != null and "player" in m and m.player != null:
		_on_player_spawned(m.player)

func _on_player_spawned(c: Node) -> void:
	_player = c as Creature
	_sleep = _player.get_component(Sleep) as Sleep if _player != null else null

func _process(_dt: float) -> void:
	var want := _desired_speed()
	if is_equal_approx(want, _applied):
		return
	_applied = want
	TimeSystem.speed = want
	Log.ev("睡眠", "时间倍率 -> ×%.0f" % want)

## 该用多快的倍率。见文件头第三节。
func _desired_speed() -> float:
	if _sleep == null or _player == null or not is_instance_valid(_player):
		return NORMAL_SPEED
	if not _player.is_alive():
		return NORMAL_SPEED          # 睡着时死了 —— 见文件头第三节的警告
	return SLEEP_SPEED if _sleep.is_sleeping() else NORMAL_SPEED

## 供调试 / 自检：当前是否处于加速态。
func is_accelerated() -> bool:
	return _applied > NORMAL_SPEED
