extends Node

## 调试日志统一出口（Autoload）。带「游戏时间戳 + 分类过滤」。
## 用法：Log.ev("生成", "猪#1 ...")
## 分类默认开关：生成/受伤/失血/死亡/需求/调试 = 开；移动 = 关（刷屏，需要时 Log.set_category("移动", true)）。

var enabled := true

var categories := {
	"生成": true,
	"受伤": true,
	"失血": true,
	"死亡": true,
	"需求": true,
	"移动": false,
	"调试": true,
}

func ev(category: String, msg: String) -> void:
	if not enabled or not categories.get(category, true):
		return
	print("[t=%5.1f][%s] %s" % [TimeSystem.elapsed, category, msg])

func set_category(category: String, on: bool) -> void:
	categories[category] = on

func toggle(category: String) -> void:
	set_category(category, not categories.get(category, true))
