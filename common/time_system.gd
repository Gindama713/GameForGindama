extends Node
## 全局时钟（Autoload）。所有生物 / 系统的时间都从它来，不自己读系统时钟。
## 暂停 = 不发 tick；快进 = 每次发更大的 dt，或一帧多发几次。
## 这样「暂停即停、可快进」是白送的（符合模拟游戏需求）。
## 底层依据：_physics_process 固定步长、确定性；Autoload 挂在树根，比主场景先处理。
##
## 【时间尺度】1 真实秒 = 1 游戏分钟（用户 2026-09-19 拍板）。
##   于是 1 游戏天 = 1440 游戏分钟 = 1440 真实秒 = 24 真实分钟。
##   `elapsed` 的单位就是**游戏分钟**（speed=1 时数值上等于真实秒数）——需求衰减等全按它走。
##   时间尺度只在这里定义：将来改「1 秒 = 几游戏分」只动 REAL_SECONDS_PER_GAME_MINUTE。
##
## 【日夜】夜晚 = [NIGHT_START_HOUR, 24) ∪ [0, NIGHT_END_HOUR)。夜里大脑会给「休息」加权（见 brain.gd）。

signal tick(dt: float)          # dt = 本次推进的游戏分钟
signal day_changed(day: int)    # 跨天时广播（存档/事件用；UI 也可直接读 day()）

## 1 真实秒 = 多少游戏分钟。改这里 = 改整体时间尺度。
const REAL_SECONDS_PER_GAME_MINUTE := 1.0
const MINUTES_PER_DAY := 1440
## 夜晚时段（小时）。20:00–06:00 = 10 小时夜。
const NIGHT_START_HOUR := 20
const NIGHT_END_HOUR := 6

var paused: bool = false
var speed: float = 1.0
var start_hour: int = 8          # 开局时刻（08:00，白天起步）
var elapsed: float = 0.0         # 游戏内累计**分钟**

var _emitted_day: int = 1

func _ready() -> void:
	elapsed = float(start_hour) * 60.0
	_emitted_day = day()

func _physics_process(delta: float) -> void:
	if paused:
		return
	# 真实秒 × 速度 ÷ 尺度 = 游戏分钟
	var d := delta * speed / REAL_SECONDS_PER_GAME_MINUTE
	elapsed += d
	var now_day := day()
	if now_day != _emitted_day:
		_emitted_day = now_day
		day_changed.emit(now_day)
	tick.emit(d)

# ---------------- 查询 ----------------

## 当前第几天（从 1 开始）
func day() -> int:
	return int(elapsed / MINUTES_PER_DAY) + 1

## 当天已过的游戏分钟（0 .. 1439.x）
func minute_of_day() -> float:
	return fmod(elapsed, MINUTES_PER_DAY)

func hour() -> int:
	return int(minute_of_day() / 60.0)

func minute() -> int:
	return int(minute_of_day()) % 60

## 是否夜晚（跨界：20:00 起算，到次日 06:00）
func is_night() -> bool:
	var h := hour()
	return h >= NIGHT_START_HOUR or h < NIGHT_END_HOUR

## "HH:MM"
func time_string() -> String:
	return "%02d:%02d" % [hour(), minute()]

## "第 N 天  HH:MM"
func day_time_string() -> String:
	return "第 %d 天  %s" % [day(), time_string()]
