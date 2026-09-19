extends Node

## 全局事件总线：系统 / UI 间解耦的信号中转。
## 连接不持引用，发射方 / 接收方释放后连接自动断（Godot 信号机制）。
## 点击猪 -> 发出 creature_clicked -> 检视面板接收，互不持有引用。

signal creature_clicked(creature: Node)
signal creature_spawned(creature: Node)   # main._spawn_pig() 生成成功即发（Minimap 重画）
signal creature_moved(creature: Node)     # Creature.move_to() 成功即发（Minimap 重画；将来脚印/噪音也听它）
signal creature_died(creature: Node)      # Creature.die()（Inspector 切尸体视图 / Minimap 重画）
signal creature_removed(creature: Node)   # DebugToolbar 清屏等"非死亡移除"（Inspector 关面板 / Minimap 重画）
