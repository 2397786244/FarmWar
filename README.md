# FarmWar / FoodWar

FarmWar 是一款使用 Godot 4 开发的多人团队对抗农场游戏。玩家需要在 Creston Town 中种植、采集、烹饪、运输和交付物资，同时使用武器、载具、无人机及各类工具与另一支队伍竞争。

项目当前处于持续开发阶段，游戏内工程名称仍为 `FoodWar`。

## 当前内容

- 单人游戏与多人游戏流程
- 红蓝双方队伍、队伍金钱与任务奖励
- 农作物种植、成熟、收获及自然资源采集
- 树木、矿石、稀有巨大作物和资源刷新
- 烹饪设备、菜谱、成品菜与队伍库存
- 玩家背包、装备、载重和耐久系统
- 枪械、魔法武器、投掷物及可放置工具
- 载具、CargoCar 货运箱存储与 CargoArea 交付
- 家禽、牲畜、Chop 养殖设施和野生动物
- 黑熊 FSM、战斗效果和服务器权威伤害
- 昼夜循环、太阳、月亮、云层和夜间路灯
- Remote 设备、无人机与摄影无人机
- F12 无 UI 截图和摄影无人机截图/录像

## 开发环境

- Godot `4.6.3` Mono
- 渲染器：Forward+
- 设计分辨率：`1920 x 1080`
- 物理引擎：Jolt Physics

建议使用与工程配置相同或更新的 Godot 4.6 Mono 稳定版本。

## 启动项目

1. 克隆仓库：

   ```bash
   git clone https://github.com/2397786244/FarmWar.git
   ```

2. 使用 Godot 4.6 Mono 导入项目根目录中的 `project.godot`。
3. 等待 Godot 完成首次资源导入。
4. 运行主场景，从主菜单选择单人游戏或多人游戏。

首次导入生成的 `.godot/` 目录不需要提交到 Git。

## 基础操作

| 操作 | 默认按键 |
| --- | --- |
| 移动 | `W` `A` `S` `D` |
| 跳跃 / 趴下时起身 | `Space` |
| 交互 | `E` |
| 打开背包 | `B` |
| 打开队伍库存 | `T` |
| 丢弃当前物品 | `Q` |
| 装弹 | `R` |
| 趴下 / 起身 | `Ctrl` |
| 地图 | `M` |
| Remote 设备列表 | `G` |
| 道具第二动作 | `C` |
| 队伍聊天 | `Y` |
| 截图 | `F12` |
| 返回 / 关闭当前界面 | `Esc` |

鼠标左键和右键的行为由当前手持武器、工具、载具或 Remote 设备决定。

## 数据配置

主要物品和玩法参数保存在 `data/`：

| 文件 | 内容 |
| --- | --- |
| `tool_definitions.json` | 武器、工具、投掷物和可放置道具 |
| `equipment_definitions.json` | 背包、胸甲和护腿装备 |
| `ingredient_definitions.json` | 农产品、原材料、矿石等物品 |
| `dish_definitions.json` | 成品菜定义 |
| `recipe_definitions.json` | 厨具菜谱 |
| `auto_cooker_recipe_definitions.json` | 自动做菜机菜谱 |
| `extractor_recipe_definitions.json` | 食材提取器配方 |
| `stand_mixer_recipe_definitions.json` | 搅拌机配方 |
| `hero_definitions.json` | 角色定义 |
| `primary_weapon_definitions.json` | 主武器定义 |
| `special_tool_definitions.json` | 专属工具定义 |
| `hero_special_tools.json` | 角色与专属道具的关联 |

修改 JSON 配置时应保持合法 JSON 格式，并注意单人和多人模式共用的数据契约。

## 目录结构

```text
assets/       GLB 模型、贴图、图标和其他美术资源
buildings/    建筑及固定设施场景
character/    玩家角色、武器和装备场景
data/         物品、装备、角色和菜谱配置
docs/         开发规范与设计文档
items/        食材、资源、动物和掉落物场景
kitchens/     厨具场景
server/       服务器配置
src/          核心 GDScript 逻辑
tests/        静态验证和系统验证脚本
tools/        内容生成、检查和开发辅助脚本
ui/           游戏界面场景
vehicles/     载具场景与配置
worlds/       地图、测试场景及服务端场景
```

## 多人架构

多人游戏中的关键玩法由服务器权威处理，包括角色和动物伤害、资源状态、载具、工具、库存、任务与奖励。客户端负责提交操作请求并渲染服务器同步的视觉代理。

涉及共享状态的新功能应同时检查：

- 单人本地权威路径
- 多人服务器权威路径
- 远端客户端视觉同步
- 断线、死亡和节点销毁后的状态释放

## 开发说明

- 不要提交 `.godot/`、导出构建、截图、临时文件或 IDE 本地设置。
- `builds/` 只用于本地导出，不属于源码仓库。
- 新增可进入背包的物品时，应同步注册对应配置和图标/模型解析。
- 新增伤害目标时，应同时检查子弹、炮弹、爆炸、命中提示和多人同步。
- 新增可交互设施时，应处理距离关闭、`Esc` 关闭和服务器排他锁释放。

## 许可证

许可证信息见 [LICENSE](LICENSE)。第三方模型、贴图、字体及其他素材仍受各自许可证约束。
