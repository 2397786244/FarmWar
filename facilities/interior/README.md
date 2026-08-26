# Interior Facilities

Place standalone indoor furniture and garage equipment scenes in this directory. The map editor discovers `.tscn` files here through the Facilities tool.

Set `metadata/map_can_overlap_water = true` on a scene root only when the facility is intentionally allowed to overlap water. The default is `false`.

Computer facilities can also set `metadata/map_can_overlap_support_objects = true`. This allows a laptop or desktop to overlap a table or the enterable building's support footprint in the map editor. The facility still has to overlap an enterable building when its catalog category is `interior`.
