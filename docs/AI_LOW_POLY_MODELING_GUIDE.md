# FarmWar 低面数 3D 资产生成规范

本文档用于把 FarmWar 当前的 3D 美术风格和 Blender 自动化流程迁移给其他 AI、开发者或资产生成代理。目标不是生成写实模型，而是稳定地产出适合独立游戏、易于识别、便于程序化修改、可以直接导入 Godot 的低面数 GLB 资产。

---

## 1. 风格目标

### 1.1 核心关键词

- Stylized low-poly
- Chunky silhouette
- Soft-toy proportions
- Clean color blocking
- No photo textures
- One-segment bevel
- Readable from gameplay distance
- Modular and AI-generatable

中文描述：

- 卡通、低面数、轮廓粗壮。
- 结构适度夸张，不追求真实机械比例。
- 使用少量大色块表达功能，不依赖贴图细节。
- 边角有轻微倒角，不使用过度圆滑的高模曲面。
- 从较远的游戏摄像机中仍能立刻认出用途和阵营。
- 每个部件有明确名称，方便 Godot、AI 或脚本继续处理。

### 1.2 不应该出现的风格

- 写实枪械比例和复杂机械内构。
- 大量细碎零件、螺丝、导轨和不可见内面。
- 4K PBR 贴图、扫描材质、磨损贴花。
- 32边以上的普通圆柱。
- 多级细分曲面、雕刻细节或高密度布尔网格。
- 依靠极细结构才能识别的轮廓。

---

## 2. Blender 与坐标规范

### 2.1 单位

```python
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
```

- Blender 1单位视为1米。
- 小型手持工具建议总长度约 `0.8–1.3m`。
- 工具在 Blender 中可以按完整尺寸建模，再在 Godot 武器场景中统一缩放。

### 2.2 朝向

- Blender 中枪口统一朝向本地 `-Y`。
- Blender 中 `+Z` 为上方。
- 导出 glTF/GLB 时启用 `export_yup=True`。
- 导入 Godot 后，武器逻辑统一以节点本地 `-Z` 作为前方。

### 2.3 原点

- 根节点原点放在握持区域上方或武器主体中心附近。
- 不把原点放在枪口、模型最底部或远离模型的位置。
- 枪口的精确发射点应在 Godot 场景中使用 `Marker3D` 设置，而不是依赖 GLB 原点。

### 2.4 Transform

导出前必须：

```python
bpy.ops.object.transform_apply(
    location=False,
    rotation=False,
    scale=True,
)
```

禁止：

- 任何轴缩放为0。
- 使用 NaN、Infinity 或奇异 Basis。
- 依赖未应用的负缩放修正朝向。

---

## 3. 形体语言

### 3.1 基础图元

优先使用：

- Cube：主体外壳、握把、瞄具、护板、按钮。
- Cylinder：枪管、能量罐、燃料罐、轴心、喷口。
- Sphere/Icosphere：果实、能量核心、小型装饰。
- Plane：透明罩、特效承载面、UI式标记。

推荐圆柱边数：

| 用途 | 顶点数 |
|---|---:|
| 小按钮、连接件 | 6–8 |
| 枪管、燃料罐 | 8 |
| 需要稍圆的主罐体 | 8–10 |
| 英雄级近景部件 | 最多12 |

### 3.2 倒角

所有主要 Cube 使用单段倒角：

```python
modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
modifier.width = 0.01  # 根据资产尺寸可调整到 0.01–0.04
modifier.segments = 1
```

规则：

- 主体倒角宽度通常为最短尺寸的 `5%–15%`。
- 小按钮可以不倒角。
- 不使用3段以上的圆滑倒角。

### 3.3 轮廓优先级

建模顺序：

1. 先完成主体、枪管、握把三个大形。
2. 确认黑色剪影下仍能识别武器类型。
3. 加入一个功能性识别部件，例如冰冻罐、火焰喷口、种子仓。
4. 最后才添加瞄具、扳机、按钮等小件。

模型缩小到预览图高度约100像素时，仍应能识别：

- 哪一端是枪口。
- 玩家从哪里握持。
- 武器的元素属性或功能。

### 3.4 连接检查

所有看似连接的部件必须真实接触或轻微穿插：

- 握把顶部与主体必须相交。
- 握把底盖与握把不能悬空。
- 燃料罐、能量罐必须有支架、端盖或与主体交叠。
- 瞄具必须接触上机匣。

程序化建模时要牢记：

```python
bpy.ops.mesh.primitive_cube_add(size=1.0)
```

此时 `obj.scale.z = 0.5` 产生的是高度约0.5的立方体，不是高度1.0。连接位置必须按最终尺寸的一半计算。

---

## 4. 材质与配色

### 4.1 材质原则

- 每件资产建议使用3–5种材质。
- 不使用纹理贴图。
- 使用 Principled BSDF 的 Base Color、Metallic、Roughness。
- 大部分表面 Roughness 为 `0.45–0.85`。
- 金属部件 Metallic 为 `0.35–0.8`。
- 塑料和木材 Metallic 接近0。

推荐函数：

```python
def make_material(name, color, metallic=0.0, roughness=0.72):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material
```

### 4.2 色彩结构

每件工具使用：

- 60%–75% 主色。
- 15%–25% 深色结构色。
- 10%–15% 高亮功能色。

示例：

#### 冰冻枪

- 主体：深海军蓝。
- 次色：深钴蓝。
- 功能色：冰蓝/青色。
- 握把：接近黑色的蓝灰色。
- 金属：低饱和蓝灰。

#### 火焰枪

- 主体：红色。
- 次色：深红或焦黑色。
- 功能色：黄色。
- 热源强调：橙色。
- 喷口内部：深灰黑。

### 4.3 色彩可读性

- 功能罐和枪口必须与主体形成明显明度差。
- 不要整件模型只有一种颜色。
- 不要使用大量接近纯白的高光材质。
- 队伍色和功能色需要分开考虑，避免蓝队拿冰冻枪时整件模型没有层次。

---

## 5. 面数与性能预算

建议预算：

| 资产类型 | 推荐三角面 |
|---|---:|
| 小型农作物 | 100–600 |
| 小型手持工具 | 300–1,500 |
| 炮塔/护盾装置 | 500–2,500 |
| 树木/岩石 | 300–2,000 |
| 模块化建筑单件 | 100–1,500 |

额外要求：

- 单个小型武器尽量控制在20个可见部件以内。
- 不为完全不可见的内部结构建模。
- 相同材质尽量复用。
- 透明材质只在明确需要时使用。
- 不使用骨骼即可完成的静态资产不要添加 Armature。

---

## 6. 命名和层级

### 6.1 文件名

格式：

```text
FTF_<Category>_<AssetName>_<Variant>.glb
```

示例：

```text
FTF_Tool_Freeze_Gun_DeepBlue.glb
FTF_Tool_Flame_Gun_RedYellow.glb
FTF_Food_Vegetable_Soup_Green.glb
```

### 6.2 根节点

使用 Empty 作为唯一根节点：

```python
root = bpy.data.objects.new("FTF_Tool_Freeze_Gun_DeepBlue", None)
bpy.context.collection.objects.link(root)
```

所有部件设置：

```python
obj.parent = root
```

### 6.3 部件名

使用英文 PascalCase，表达功能：

```text
Receiver
Grip
GripCap
ColdBarrel
CryoCanister
FuelCell
NozzleBell
Trigger
RearSight
```

禁止使用最终文件中的：

```text
Cube.001
Cylinder.017
Object
Mesh
```

Blender 内部数据块名称不重要，但导出的对象节点必须有语义。

---

## 7. 自动生成脚本结构

推荐脚本分层：

```python
# 1. CLI 和输出目录
# 2. clear_scene()
# 3. make_material()
# 4. add_cube()/add_cylinder()/add_sphere()
# 5. create_root()
# 6. build_<asset>()
# 7. export_glb()
# 8. main
```

所有资产函数应做到：

- 可以在 `--factory-startup` 环境运行。
- 不依赖当前打开的 `.blend` 文件。
- 输出目录不存在时自动创建。
- 重复运行会覆盖同名结果，不产生随机名称。
- 生成完成后打印输出路径。

运行方式：

```powershell
blender.exe --background --factory-startup --python generate_assets.py
```

如果需要外部输出目录：

```powershell
blender.exe --background --factory-startup \
  --python generate_assets.py -- \
  --output "D:\output"
```

---

## 8. GLB 导出规范

```python
bpy.ops.export_scene.gltf(
    filepath=output_path,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_yup=True,
)
```

导出前检查：

- 根节点名称正确。
- 所有对象都属于根节点。
- 不存在相机和灯光。
- 不存在隐藏的测试模型。
- Scale不是0且已应用。
- 材质名称具有语义。
- 枪口朝向 Blender `-Y`。
- 文件名符合规范。

---

## 9. Godot 导入规范

GLB 只负责视觉模型。正式武器场景应另外创建：

```text
WeaponRoot (Node3D)
├── ImportedGLB
├── Muzzle (Marker3D)
├── RayCast3D
├── GPUParticles3D
└── AudioStreamPlayer3D
```

注意：

- 发射方向由 `Marker3D/RayCast3D` 决定，不依赖 GLB 内部节点。
- 碰撞体使用 Godot 原生 CollisionShape3D，不从复杂视觉网格自动生成。
- 第一人称模型通常关闭阴影或调整渲染层，避免穿模。
- 材质若出现异常辉光，检查导入材质的 Emission。
- GLB 更新后保持文件名不变，Godot 会重新导入并保留场景引用。

---

## 10. 自动质量检查

生成后至少完成以下检查：

### 10.1 文件检查

- GLB 文件存在且大小大于0。
- Blender 能重新导入该 GLB。
- 导入后对象数量合理。
- 没有丢失材质。

### 10.2 视觉检查

自动生成一张 `900×650` 或更大的预览图：

- 3/4视角。
- 深灰背景。
- 一盏主光、一盏冷色补光。
- 模型完全进入画面。
- 检查悬空部件、穿插错误、枪口方向和颜色层次。

### 10.3 结构检查

- 根节点只有一个。
- 所有可见对象有语义名称。
- 无零缩放。
- 无极端坐标。
- 总包围盒符合预期尺寸。
- 枪口、握把和主体连续。

---

## 11. 常见失败与修正

### 部件悬空

原因：

- 误把 Cube 的 `scale` 当成半尺寸。
- 只根据中心位置判断，没有计算最终包围盒。

修正：

- 明确 `primitive_cube_add(size=1.0)` 后最终尺寸。
- 让连接部件轻微重叠 `0.01–0.04m`。

### 模型过于写实

原因：

- AI加入太多真实枪械零件。
- 使用过细枪管和复杂握把。

修正：

- 删除不影响轮廓的零件。
- 增粗枪管、握把和功能罐。
- 保留最多一个主识别装置。

### 导入Godot后方向错误

修正：

- Blender 枪口统一朝 `-Y`。
- 使用 `export_yup=True`。
- Godot 场景中通过父 Node3D 做一次统一朝向校正。
- 不逐个旋转模型内部零件。

### 材质一起变色

原因：

- 多个对象共享材质后直接修改共享资源。

修正：

- 颜色固定的资产直接共享材质。
- 运行时需要独立变色时，在 Godot 使用材质副本或实例 Shader 参数。

---

## 12. 可直接交给其他 AI 的任务模板

```text
你要使用 Blender Python 生成一个 FarmWar 风格的低面数3D资产。

资产：
- 类型：{武器/作物/建筑/厨具}
- 名称：{名称}
- 主色：{主色}
- 辅助色：{辅助色}
- 功能色：{功能色}
- 游戏用途：{用途}

必须遵守：
1. 风格为 stylized low-poly、chunky、soft-toy proportions。
2. 只使用基础图元和单段倒角，不使用贴图和高模雕刻。
3. 普通圆柱使用6–10个顶点，最多12个。
4. 优先保证远距离轮廓，不添加不影响轮廓的细碎零件。
5. 所有看似连接的零件必须真实接触或轻微穿插，不得悬空。
6. Blender单位为米，+Z向上，武器枪口朝本地-Y。
7. 创建唯一语义化Empty根节点，所有部件使用英文功能名称。
8. 不创建相机、灯光、骨骼或复杂碰撞体。
9. 导出前应用Scale，禁止零缩放。
10. 输出GLB、完整Blender Python生成脚本和一张3/4视角预览图。

材质：
- 只使用Principled BSDF基础颜色、Metallic、Roughness。
- 总材质数量控制在3–5种。
- 使用60–75%主色、15–25%深色结构色、10–15%高亮功能色。

性能：
- 小型工具控制在300–1500三角面。
- 可见部件尽量少于20个。

导出：
- 格式GLB。
- export_apply=True。
- export_yup=True。
- 文件名：FTF_{Category}_{AssetName}_{Variant}.glb。

完成后自行重新导入GLB并渲染预览，检查轮廓、比例、悬空部件、材质和朝向。
```

---

## 13. 本次元素武器参考

### 冰冻枪

```text
名称：FTF_Tool_Freeze_Gun_DeepBlue
尺寸：小型单手工具
主体：深蓝色粗壮机匣
识别点：冰蓝色横向能量罐、三叉聚焦枪口
枪口：短枪管、冰蓝枪口环、深色中心孔
禁止：写实液氮管线、透明高模玻璃、细碎雪花装饰
```

### 火焰枪

```text
名称：FTF_Tool_Flame_Gun_RedYellow
尺寸：小型单手工具
主体：红色粗壮机匣
识别点：黄色燃料罐、黄色喇叭喷口、橙色热源
枪口：短喷管、八边形扩张喷口、深色中心孔
禁止：写实军用喷火器背包、长软管、复杂阀门
```

