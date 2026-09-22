class_name NeedIds
extends RefCounted

## 需求 id（`NeedDef.id`）的**唯一事实来源**。⚠ 加新需求只在这里加。
##
## 【为什么单独一个类】此前同一个字符串被散在 **8 个文件**里各声明一遍：
##   · `"fatigue"` × 4 —— `brain.gd` / `needs.gd` / `sleep.gd` / `sprint.gd`
##   · `"water"`   × 3 —— `drinking.gd` / `grazing.gd` / `reproduction.gd`
##   · `"food"`    × 2 —— `grazing.gd` / `reproduction.gd`
##   · `"warmth"`  × 1 —— `thermal.gd`
##   而且好几处的注释都写着"与 XXX 同字面量" —— 那正是**"同值复制"的自我供认**：
##   改一处忘一处，而且没人知道还有谁在用这个字符串（隐式耦合）。
##   （`Groups` 类是同一个病、同一个药方，见 `common/groups.gd`。）
##
## 【为什么这种复制特别危险 —— 双向静默失效】
##   `.tres` 里改了 `id` 而漏改某一处常量 ⇒ `Needs.need_by_id()` 返回 `null` ⇒
##   而每个调用点都写了 `if n == null: return` 的兜底（那本身是好习惯）⇒
##   **不报错、不崩溃，只是那个机制悄悄不工作了**。
##   例：只改 `sprint.gd` 那处常量 ⇒ **疾跑永远不消耗体力，零日志**。
##
## 【加固】`ALL` 供 `DefValidator` 对账：数据里每个 `NeedDef.id` 都必须在这里登记。
##   于是"改 `.tres` 漏改常量"与"改常量漏改 `.tres`"**两个方向都会在启动期报错**（§6.10）。
##
## 【为什么不放进 `Needs` 组件】`Sprint` / `Thermal` / `Grazing` / `Reproduction` 都要读需求 id，
##   而它们**并不认识 `Needs`**（只用 `requires()` 声明硬依赖）。往 `Needs` 里塞，
##   等于让"需求的消费者"反向依赖"需求的持有者"；放在这个中立的常量类里，
##   各方都只认识它、彼此互不认识（与 `Groups` 同一个理由）。

## 饱食度。`Grazing` 吃草回它、`Reproduction` 拿它当营养门槛。
const FOOD := "food"
## 口渴。`Drinking` 在岸边补它、`Grazing` 每口顺带解一点。
const WATER := "water"
## 保暖。`Thermal` 夜里扣、白天回。
const WARMTH := "warmth"
## 疲劳。`Needs` 按劳累档扣它、`Sleep` 回它、`Sprint` 拿它当**体力上限**（不是独立数值）。
const FATIGUE := "fatigue"
## 憋气。⚠ **当前无任何物种引用**（`creature/pig/data/need_breath.tres` 是孤儿文件，
##   见《项目结构》§6）。保留在这里是为了让 `ALL` 与磁盘上的 `.tres` 对得上 ——
##   否则校验器会把那份孤儿文件报成"id 写错了"。
const BREATH := "breath"

## 全部需求 id —— 供 `DefValidator` 核对"数据里的 id 有没有写错"。
## ⚠ 加新需求：**这里加常量 + 加进本清单 + 配一份 `.tres`**（三处，缺一会被校验器抓到）。
const ALL: Array[String] = [FOOD, WATER, WARMTH, FATIGUE, BREATH]
