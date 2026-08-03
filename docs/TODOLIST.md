# TODO List

## WheatSentry Multiplayer Debug

- Status: Deferred; do not change the current WheatSentry implementation in this task.
- Problem: WheatSentry has inconsistent multiplayer presentation. Its visible rotation, target tracking direction, firing direction, and hit result can diverge between the server-authoritative simulation and remote client visuals.
- Debug scope: Verify the complete sequence for startup rotation, target acquisition, server target selection, authoritative firing direction, projectile spawning, world snapshots, and client-side visual interpolation.
- Expected result: Every client should see the sentry rotate toward the same target before firing, with a projectile visual that follows the server-authoritative firing direction and can hit that target consistently.

## Ingredient Extractor Units

- Status: Deferred until the Ingredient Extractor is implemented.
- Extracted wheat flour and sugar must be produced only in multiples of `0.25 kg`.
- Extracted yeast must be produced only in multiples of `0.01 kg`.
- The extractor must use the configured `pickup_unit_kg` from `IngredientCatalog` rather than hard-coded weights, so future balance changes remain consistent with shop, pickup, and recipes.

## 添加Stump，和树木一样可以被摧毁掉落log，但是掉落的log只有树木的1/3
三个树木的glb我放在了nature下面

## 在other_items下面的crate文件夹内创建了两个LootChest的glb，一个是Common一个是Golden
后续要实现战利品箱的功能，玩家可以打开，打开之后里面弹出一些掉落物


## tools下面放了一个空桶，一个水桶，一个牛奶桶
空桶到水体边上，对着水面可以得到一个水桶
对着安格斯牛可以得到牛奶桶

## tools下面新增了 高大的BrickWall，一个WIreMeshGate、一个WireMeshWall 一个 LogWall
## tools下面新增了一个木制的观测塔。需要爬梯子
