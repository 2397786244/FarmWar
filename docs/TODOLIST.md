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
