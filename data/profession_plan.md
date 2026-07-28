## 当前已经设计的玩家职业
+ Farmer 农夫
+ Cook 厨师
+ Guard 守卫
+ Apothecary 药剂师
+ Assistant 助手
+ Engineer 工程师
+ Mage 魔法师
+ Prospector  调查员
+ Rider 车手
+ Trickster 捣蛋鬼

## 当前已经设计的手持工具和武器
+ Eater 吸能枪  1 
+ FlameGun 火焰枪 2
+ FreezeGun 冰冻枪  3
+ NailGun 射钉枪  4 
+ Revolver 左轮手枪  5 
+ SproutBlaster 种子播撒器  6
+ Wand 魔杖  —> 魔法师专属
+ Wreck 破坏者  7
+ BugCannon 虫虫大炮 -> 魔法师专属
### 下面的还在规划中，均是角色通用武器
+ Pistol 消音手枪  8
+ 栓动步枪（远距离）  9
+ 榴弹炮  10
+ Axe 斧子（近战1）  11
+ PickAxe 镐子（近战2）  12
+ 木棍（近战3）  13
## 当前已经设计的可放置道具
+ AntiAir 防空车    x  
+ AutoShooter 固定炮台  x
+ NormalDrone 普通无人机（投弹和运货）  x
+ ShieldDoor 防护门    x
+ WheatSentry 麦田守卫  x
+ 砖墙,通用
### 规划中的
+ Fertilizer 肥料发射器   x
+ TechDrone 高级无人机  x
+ PlantProtector 植物保护器   x
+ MedicinePistol 药物手枪   x
+ SmallMouse 小老鼠（远程工具）  x
+ SignalAugment 信号增强塔  x
+ SignalJam 信号干扰器  x
+ BigMouth 吞噬陷阱
+ Trap 地刺陷阱 （对人类和车辆有效）
+ VehicleTracker（让对方的载具暴露，在地图、屏幕上面实时显示跟踪）
## 每个职业的特殊工具/道具 分配，计划每个职业可以任意在1-13之间选择3个工具/武器 + 1个职业专属工具、武器
+ 职业专属武器和工具的分配，希望每个职业至少有2个专属工具：
+ Farmer 农夫 -> ，PlantProtector(附近的土地免受雷击，虫子攻击),Fertilizer（有概率让作物产生变异的巨大型作物），FarmRunner（自动收获播种机） | 种地，农业产出
+ Cook 厨师     ->   香料喷射枪（追踪）,野战厨房，自动做菜机   ｜ 烹饪，农业产出
+ Guard 守卫  -> AntiAir(阻止BoomBullet这样的大型炮弹),ShieldDoor,AutoShooter   ｜  本土守护
+ Apothecary 药剂师  -> MedicinePistol（治疗手枪）,MedicineCannon（药物大炮，发出药物气雾），TranquilizerPistol（镇静手枪，对敌方发射）     ｜ 支援
+ Assistant 助手   -> NormalDrone,WheatSentry，Shield（手持护盾）  ｜ 本土守护或者完成限时任务
+ Engineer 工程师  -> SignalJam,TechDrone,SmallMouse  ｜  进攻或帮助防护
+ Mage 魔法师  -> Wand,BugCannon，RiftBook ｜ 进攻
+ Prospector  调查员 -> TraceTagger（扫描追踪各种工具和人物）,SignalAugment，ProspectScanner，SurveyRider（测绘骑手） ｜ 进攻
+ Rider 车手  -> ToolKit,VehicleTracker，BoomBuggy（自爆遥控车） ｜ 进攻
+ Trickster 捣蛋鬼  -> BigMouth,Trap，FakePlayer（产生一个假人，会制作一个专属的假人外观，如果攻击假人，自己的位置会被标记）  ｜ 防护
## 详细的规划：
# FarmWar 职业专属工具规划（当前统一版）

## 一、装备规则

每名玩家携带：

```text
3 个通用手持工具 / 武器
+ 1 个职业专属工具
```

每个职业拥有 3 个专属候选工具，玩家在开局或重生时从中选择 1 个携带。

其中：

* `Wand` 和 `BugCannon` 虽然属于手持武器，但只能由 Mage 作为职业专属选择。
* `MedicinePistol`、`TranquilizerPistol`、`ToolKit`、`RiftBook`、`TraceTagger` 等属于手持职业工具，不应归入“可放置道具”。
* `AntiAir`、`AutoShooter`、`ShieldDoor`、`FarmRunner`、`SignalAugment` 等属于可放置或可部署职业设备。
* `NormalDrone`、`TechDrone`、`BoomBuggy`、`SmallMouse` 属于远程操控单位或一次性远程设备。

---

## 二、需要更新或删除的旧设计

| 旧记录                         | 当前统一结果                                      |
| --------------------------- | ------------------------------------------- |
| RemedyMist 药雾发生器            | 改为 `MedicineCannon` 药物大炮，发射药物气雾并形成范围治疗、净化区域 |
| NitroKit 氮气推进组件             | 删除，不作为 Rider 专属                             |
| TowWinch 牵引绞盘               | 删除，不作为 Rider 专属                             |
| CargoModule / CargoRig      | 删除，不作为 Rider 专属                             |
| EchoProbe 回声探测器             | 删除，不作为调查员专属                                 |
| PhantomBeacon 假工具、假载具、假人物信号 | 收束为 `FakePlayer`，只生成假人物诱饵                   |
| TraceTagger 可追踪车辆           | 调整为只追踪人物与工具 / 部署物；车辆由 VehicleTracker 专门追踪   |
| RiftAnchor 被称为单独设备          | 由 `RiftBook` 这个手持工具创建和回跳，Anchor 本身是技能生成物    |

---

# 三、职业专属工具总表

| 职业                 | 战场定位                  | 专属工具                      | 类型            | 功能描述                                                                                                                         |
| ------------------ | --------------------- | ------------------------- | ------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **Farmer 农夫**      | 农业生产、农田防护、高风险资源成长     | **PlantProtector 植物保护器**  | 可放置防护设备       | 在一定范围内保护农田、作物与农业设备，显著降低虫害、雷击、火焰、爆炸等对作物的破坏。建议采用能量值或耐久机制，而非永久完全免疫。                                                             |
|                    |                       | **Fertilizer 肥料发射器**      | 手持农业工具        | 向农田或作物施加肥料，加快生长、提高品质，并有概率产生巨大变异作物。巨大作物价值高，但更显眼、更容易被敌方抢夺或破坏。                                                                  |
|                    |                       | **FarmRunner 自动播种收获机**    | 可放置农业机器       | 自动在指定农田内播种、收获并重新补种普通作物，将收获物输出为原料箱放在农田边缘。不能自动处理巨型变异作物、稀有作物或严重虫害作物。                                                            |
| **Cook 厨师**        | 食材转化、订单推进、团队料理增益      | **SpiceSprayer 香料喷射枪**    | 手持控场工具        | 喷射辣椒粉、油脂、酱汁等香料。命中敌人后使其更容易被追踪、移动或瞄准受扰；命中车辆可造成打滑、转向迟钝；喷到地面可形成短暂减速或阻路区域。低伤害，重点是控场与追踪。                                           |
|                    |                       | **FieldKitchen 野战厨房**     | 可放置烹饪台        | 消耗农作物和食材制作高价值料理、特殊订单料理与短时团队增益餐。适合处理巨型作物、稀有食材和高风险高收益订单。                                                                       |
|                    |                       | **AutoCooker 自动做菜机**      | 可放置自动化设备      | 预设目标料理后，自动进行清洗、切配、烹饪、装盒，批量制作标准料理。只能做普通订单餐，不应替代 FieldKitchen 的高级料理和巨型作物料理。                                                    |
| **Guard 守卫**       | 基地守卫、道路封锁、关键点防护       | **AntiAir 防空车**           | 可放置 / 可驾驶防空设备 | 拦截 BoomBullet、大型炮弹、无人机或其他空中高威胁目标。主要保护基地、厨房、车队和交付区。                                                                           |
|                    |                       | **ShieldDoor 防护门**        | 可放置防御设施       | 在道路、仓库入口、农田入口或关键通道建立固定防线。阻挡敌方直线推进和车辆冲入，但不应完全封死所有地图路线。                                                                        |
|                    |                       | **AutoShooter 固定炮台**      | 可放置自动防御设施     | 自动攻击进入警戒范围的敌方玩家、无人机或轻型目标。适合守农田、仓库、厨房出口、道路节点和交付点外围。                                                                           |
| **Apothecary 药剂师** | 治疗、净化异常状态、干扰敌方关键交互    | **MedicinePistol 药物手枪**   | 手持治疗武器        | 对友军发射药物针剂，提供精准单体治疗、紧急救援和基础异常状态缓解。适合保护搬运者、司机、修车人员和关键职业。                                                                       |
|                    |                       | **MedicineCannon 药物大炮**   | 手持范围支援武器      | 发射药物气雾，在落点形成短暂范围治疗与净化区域。可缓解燃烧、冰冻、虫害、减速等状态，适合守交付点、保护车队和巨型作物采收区。                                                               |
|                    |                       | **TranquilizerPistol 镇静手枪**  | 手持敌方干扰武器      | 对敌方发射低伤害镇静针。命中后降低采收、搬运、修车、装卸、烹饪、部署和交付效率；连续命中可短时间阻止其驾驶与关键交互。重点是打断供应链，而非直接击杀。                                                  |
| **Assistant 助手**   | 运输辅助、限时任务、低成本防守、地面护送  | **NormalDrone 普通无人机**     | 远程操控单位        | 小批量运输原料箱、料理箱、补给与任务物资；可执行轻度投弹或物资投递。适合跨越部分地形、紧急配送和前线补给。                                                                        |
|                    |                       | **WheatSentry 麦田守卫**      | 可放置警戒设施       | 低成本农田警戒与自动防御单位，适合布置在农田、作物仓库、乡间道路和侧翼入口。伤害不宜过高，重点是报警、拖延和阻止偷资源。                                                                 |
|                    |                       | **AreaProtector 区域护盾**    | 手持大型护盾        | Assistant 举起后形成可移动的大型正面掩体，阻挡子弹、射钉、部分火焰与正面爆炸冲击。可保护抱箱玩家、修车 Rider、采收 Farmer 和交付队伍。护盾有耐久，不能防侧后方、脚下陷阱和大范围爆炸。                      |
| **Engineer 工程师**   | 电子干扰、设施修理、科技渗透、设备破坏   | **SignalJam 信号干扰器**       | 可放置信号设备       | 干扰敌方 VehicleTracker、无人机、信号塔和远程协同设备。效果应以信息延迟、范围缩短、控制不稳定为主，而不是让全体设备永久停机。                                           |
|                    |                       | **TechDrone 高级无人机**       | 远程操控单位        | 可扫描、维修友方设备、短暂干扰或黑入敌方科技建筑。适合处理炮台、信号设备、厨房自动化设备和无人机系统。                                                                          |
|                    |                       | **SmallMouse 小老鼠**        | 远程渗透工具        | 小型遥控渗透单位，可钻入狭窄位置，接近敌方设施、车辆或供能点，造成局部故障、暴露弱点或干扰设备运行。                                                                           |
| **Mage 魔法师**       | 中远距离魔法输出、虫害骚扰、绕后渗透    | **Wand 魔杖**               | 手持魔法武器        | 精准型中远距离魔法攻击工具。可承担法术弹、击退、穿透、诅咒或短暂失能等作用，但应与 FlameGun、FreezeGun 保持不同的攻击体验。                                                      |
|                    |                       | **BugCannon 虫虫大炮**        | 手持魔法骚扰武器      | 发射魔法虫群，对玩家造成轻度持续干扰，降低交互效率并影响视野或瞄准；对农田造成虫害；对防御设施与无人机造成运行干扰；可在地面形成短时虫群区域。                                                      |
|                    |                       | **RiftBook 裂隙之书**         | 手持位移工具        | 第一次使用：一道闪电落到目标位置，生成带光柱效果的 `RiftAnchor`。第二次使用：Mage 短暂施法后传送至 Anchor 位置，Anchor 随即消失。完成后进入冷却，才能再次创建新的 Anchor。不能携带货物、巨型作物或驾驶载具传送。 |
| **Prospector 调查员** | 资源侦察、地图测绘、进攻路线规划 | **SignalAugment 信号增强塔**   | 可放置信号设备       | 提升附近己方的信息能力，包括地图更新、无人机协同和设备共享信息。可与 VehicleTracker、NormalDrone、AutoShooter 形成联动。                     |
|                    |                       | **ProspectScanner 资源扫描器** | 手持资源探测工具      | 探测矿石、燃油、稀有食材、特殊种子、巨型作物相关资源与地图事件资源。优先显示方向、距离和大致价值，而不是直接全图精确透视。                                                                |
|                    |                       | **SurveyRider 测绘骑手**       | 可驾驶测绘载具        | 调查员部署后驾驶的轻型双轮载具，用于快速侦察、资源测绘和短距离机动。                                                                        |
| **Rider 车手**       | 车辆维护、载具追踪、物流截击、道路突袭   | **ToolKit 修车工具箱**         | 修车 |
|                    |                       | **VehicleLocator 载具追踪器**  | 手持载具追踪工具      | 锁定敌方载具，使其在地图和屏幕中暴露位置、移动方向或最后已知位置。只追踪车辆，不追踪人物和工具。                                                                             |
|                    |                       | **BoomBuggy 爆爆小车**        | 遥控一次性爆破单位     | 部署后遥控驾驶小型自爆车，接近敌方车辆、卸货区、道路节点或交付点后手动引爆或碰撞引爆。主要作用是打断运输、制造车辆故障、迫使货物掉落和制造抢货窗口。可被枪械、炮台和干扰器提前处理。                                   |
| **Trickster 捣蛋鬼**  | 埋伏、骗位、道路破坏、心理威慑       | **BigMouth 吞噬陷阱**         | 可放置伏击陷阱       | 可伪装成补给箱、作物箱、灌木或普通场景物。触发后将玩家吞住，造成短暂控制、低至中等持续伤害和救援压力。建议允许队友攻击 BigMouth 救出被吞玩家，避免无提示秒杀。                                         |
|                    |                       | **Trap 地刺陷阱**             | 可放置道路陷阱       | 对人物与车辆都有效。可造成伤害、减速、定身、爆胎、转向失控或短时故障。适合放在农田入口、狭窄道路、车队路线、厨房后方和交付点侧路。                                                            |
|                    |                       | **FakePlayer 假人诱饵**       | 可放置伪装诱饵       | 生成一个拥有专属外观的假人物模型，用于吸引敌方靠近、浪费火力或误判队伍位置。敌方攻击假人后，攻击者自身会被标记并暴露给 Trickster 队伍。适合与 BigMouth、Trap 和侧翼伏击配合。                          |

---
# 四、核心专属工具边界
| 系统              | 专属职责                | 不应承担的职责              |
| --------------- | ------------------- | -------------------- |
| VehicleTracker  | 追踪载具与运输路线           | 不追踪人物、工具、陷阱          |
| ProspectScanner | 寻找矿石、燃油、稀有食材和地图资源事件 | 不扫描敌人位置              |
| SignalAugment   | 强化己方情报共享与设备协同       | 不提供全图透视              |
| SignalJam       | 让敌方情报延迟、失真或缩短距离     | 不永久关闭所有设备            |
| PlantProtector  | 保护农田、作物和农业设施        | 不保护整队玩家，也不提供万能护盾     |
| AreaProtector     | 保护正面推进与搬运队          | 不封锁侧后方、地面陷阱和高空区域攻击   |
| BoomBuggy       | 道路突袭、打断交付和载具行动      | 不应一击摧毁满血重型设施或秒杀满血玩家  |
| FakePlayer      | 欺骗敌方注意与诱导攻击         | 不伪造真实货物、车辆、积分或订单完成状态 |
| RiftBook        | Mage 自身绕后、撤离、切入     | 不允许携带货物、车辆或巨型作物传送    |
---

# 五、职业组合的主要战术方向

| 职业         | 选择方向示例                                                           |
| ---------- | ---------------------------------------------------------------- |
| Farmer     | PlantProtector 守农田；Fertilizer 赌巨型作物；FarmRunner 保证普通订单原料稳定产出。     |
| Cook       | SpiceSprayer 负责追踪与控场；FieldKitchen 做高价值料理；AutoCooker 批量完成普通订单。    |
| Guard      | AntiAir 防空；ShieldDoor 封锁路线；AutoShooter 守关键节点。                    |
| Apothecary | MedicinePistol 救单人；MedicineCannon 守区域；TranquilizerPistol 打断敌方运输和交互。 |
| Assistant  | NormalDrone 负责小批量物流；WheatSentry 守农田；CargoShield 护送车队与抱箱队伍。       |
| Engineer   | SignalJam 压制敌方情报；TechDrone 处理设备；SmallMouse 进行低位渗透和局部破坏。          |
| Mage       | Wand 提供法术输出；BugCannon 骚扰生产链；RiftBook 绕后和撤离。                      |
| Prospector | TraceTagger 找人和工具；SignalAugment 放大团队情报；ProspectScanner 找地图资源机会。  |
| Rider      | ToolKit 保障己方车辆；VehicleTracker 锁定敌方运输；BoomBuggy 主动截停和爆破物流线。       |
| Trickster  | BigMouth 强伏击；Trap 破坏道路与车辆；FakePlayer 诱导敌方暴露。                     |


# 版本号设定
+ 当前是alpha版本，用日期记录，服务器就是FarmWarServer_a0709,客户端就是FarmWar_a0709
