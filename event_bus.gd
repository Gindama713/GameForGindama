extends Node

## 全局事件总线：系统 / UI 间解耦的信号中转。
## 连接不持引用，发射方 / 接收方释放后连接自动断（Godot 信号机制）。
## 点击猪 -> 发出 creature_clicked -> 检视面板接收，互不持有引用。

signal creature_clicked(creature: Node)
signal creature_spawned(creature: Node)
signal creature_died(creature: Node)
