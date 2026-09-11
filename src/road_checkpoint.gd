extends Area3D
class_name RoadCheckpoint

## Authority-side road checkpoint controller.
##
## The checkpoint is intentionally an Area3D rather than a placeable facility:
## its saved transform/shape describes the gameplay region while the existing
## Facility/Defense tools remain independently editable.  Static members are
## discovered by group/class and by position, so maps do not need to store a
## fragile hand-authored list of node paths.

signal alarm_changed(active: bool, reason: String)
signal member_registered(member: Node)
signal member_unregistered(member: Node)
signal access_state_changed(allowed: bool)

const ACCESS_CARD_ID := "road_access_card"
const CHECKPOINT_GROUP := "road_checkpoints"
const DEFENSE_MEMBER_GROUP := "ai_demolition_target"
const MEMBER_RECONCILE_INTERVAL := 0.35
const OCCUPANT_RECONCILE_INTERVAL := 0.15

@export var checkpoint_id := ""
@export var allowed_team_ids: PackedStringArray = PackedStringArray(["red", "blue"])
@export var access_card_id := ACCESS_CARD_ID
@export var damage_alarm_threshold := 100.0
@export var alarm_timeout_seconds := 300.0
@export var barrier_lower_delay_seconds := 10.0
@export var area_size := Vector3(24.0, 5.0, 24.0)
@export var show_boundary := true
@export var boundary_color := Color(1.0, 0.55, 0.12, 0.9)

var alarm_active := false
var alarm_reason := ""
var alarm_remaining := 0.0

## Stable member id -> Node.  The id is persisted by the facility/map systems
## when available and falls back to a path only for unregistered test nodes.
var _members: Dictionary = {}
var _member_connections: Dictionary = {}
var _barriers: Dictionary = {}
var _blockers: Dictionary = {}
var _occupants: Dictionary = {}
var _barrier_occupants: Dictionary = {}
var _member_damage: Dictionary = {}
var _alarm_sources: Dictionary = {}
var _processed_damage_event_ids: Dictionary = {}
var _member_scan_elapsed := 0.0
var _occupant_scan_elapsed := 0.0
var _empty_barrier_elapsed := 0.0
var _last_access_allowed := false
var _boundary_root: Node3D
var _pending_network_state: Dictionary = {}
var _last_area_size := Vector3.ZERO
var _last_show_boundary := true


func _ready() -> void:
	add_to_group(CHECKPOINT_GROUP)
	set_meta("road_checkpoint", true)
	_apply_area_shape()
	_setup_boundary()
	_last_area_size = area_size
	_last_show_boundary = show_boundary
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not area_exited.is_connected(_on_area_exited):
		area_exited.connect(_on_area_exited)
	# Hit3D areas on ChainLinkFence are not bodies on the root collision layer.
	# Defer the first scan until all map facilities have completed _ready().
	call_deferred("_reconcile_membership")
	call_deferred("_reconcile_occupants")


func _process(delta: float) -> void:
	if _last_area_size != area_size or _last_show_boundary != show_boundary:
		_apply_area_shape()
		if is_instance_valid(_boundary_root):
			_boundary_root.queue_free()
			_boundary_root = null
		_setup_boundary()
		_last_area_size = area_size
		_last_show_boundary = show_boundary
	# Clients also rescan membership so a replicated/streamed barrier that is
	# created after the checkpoint can consume a pending network snapshot. This
	# is bookkeeping only; damage, access and alarm decisions stay authority-side.
	_member_scan_elapsed += delta
	if _member_scan_elapsed >= MEMBER_RECONCILE_INTERVAL:
		_member_scan_elapsed = 0.0
		_reconcile_membership()
	if not _is_authority():
		return
	_occupant_scan_elapsed += delta
	if _occupant_scan_elapsed >= OCCUPANT_RECONCILE_INTERVAL:
		_occupant_scan_elapsed = 0.0
		_reconcile_occupants()
	_update_access_and_barriers(delta)
	if alarm_active:
		alarm_remaining = maxf(0.0, alarm_remaining - delta)
		if alarm_remaining <= 0.0:
			_clear_alarm("timeout")


func refresh_visuals() -> void:
	## Editor/property-load hook shared with the other auxiliary Area tools.
	_apply_area_shape()
	if is_instance_valid(_boundary_root):
		_boundary_root.queue_free()
		_boundary_root = null
	_setup_boundary()
	_last_area_size = area_size
	_last_show_boundary = show_boundary


func _is_authority() -> bool:
	return not is_instance_valid(GameAuthority) or not GameAuthority.is_client_proxy()


func _apply_area_shape() -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		return
	var box := collision_shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		collision_shape.shape = box
	box.size = Vector3(
		maxf(1.0, area_size.x),
		maxf(1.0, area_size.y),
		maxf(1.0, area_size.z)
	)
	collision_shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	collision_layer = 1024
	# Character, vehicle, tool Hit3D and RoadBarrier TestEnterArea layers.
	collision_mask = 8 | 8192 | 128 | 512
	monitoring = true
	monitorable = true


func _setup_boundary() -> void:
	if not show_boundary:
		return
	_boundary_root = Node3D.new()
	_boundary_root.name = "CheckpointBoundary"
	add_child(_boundary_root)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = boundary_color
	material.emission_enabled = true
	material.emission = boundary_color
	material.emission_energy_multiplier = 1.2
	var half := Vector3(maxf(1.0, area_size.x), 0.0, maxf(1.0, area_size.z)) * 0.5
	var y := 0.03
	_add_boundary_line(Vector3(0.0, y, -half.z), Vector3(half.x * 2.0, 0.035, 0.06), material)
	_add_boundary_line(Vector3(0.0, y, half.z), Vector3(half.x * 2.0, 0.035, 0.06), material)
	_add_boundary_line(Vector3(-half.x, y, 0.0), Vector3(0.06, 0.035, half.z * 2.0), material)
	_add_boundary_line(Vector3(half.x, y, 0.0), Vector3(0.06, 0.035, half.z * 2.0), material)


func _add_boundary_line(line_position: Vector3, line_size: Vector3, material: Material) -> void:
	if _boundary_root == null:
		return
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = line_size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = line_position
	_boundary_root.add_child(mesh_instance)


func contains_world_position(world_position: Vector3) -> bool:
	var local := to_local(world_position)
	var half := area_size * 0.5
	var center_y := maxf(0.5, area_size.y * 0.5)
	return absf(local.x) <= maxf(0.5, half.x) \
		and absf(local.z) <= maxf(0.5, half.z) \
		and local.y >= -0.25 and local.y <= center_y + half.y + 0.25


func _reconcile_membership() -> void:
	if not is_inside_tree():
		return
	var seen: Dictionary = {}
	# Position scanning is required for ChainLinkFence: its root body has
	# collision_layer 0 and only its child Hit3D Area is queryable.
	for group_name in [DEFENSE_MEMBER_GROUP, "chain_link_fences", "road_barriers", "road_blockers"]:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if not candidate is Node3D or not is_instance_valid(candidate):
				continue
			if not _is_checkpoint_member(candidate as Node):
				continue
			if candidate is RoadCheckpoint or not contains_world_position((candidate as Node3D).global_position):
				continue
			var member := candidate as Node
			var member_id := _member_id(member)
			seen[member_id] = true
			_register_member(member)
	for area in get_overlapping_areas():
		var member := _resolve_member_root(area)
		if member == null or not _is_checkpoint_member(member):
			continue
		var member_id := _member_id(member)
		seen[member_id] = true
		_register_member(member)
	var stale_ids: Array = []
	for member_id_value in _members.keys():
		var member_id := str(member_id_value)
		# A member can be queue_free()'d between scans.  Do not assign a freed
		# Object wrapper to a typed Node variable: Godot reports that assignment
		# itself as an error before is_instance_valid() can inspect it.
		var member_value: Variant = _members[member_id]
		if not is_instance_valid(member_value) or not seen.has(member_id):
			stale_ids.append(member_id)
	for member_id in stale_ids:
		_unregister_member(member_id)
	if not _pending_network_state.is_empty():
		_apply_pending_network_state()


func _is_checkpoint_member(node: Node) -> bool:
	if node == null or node is RoadCheckpoint:
		return false
	if node.is_in_group("road_blockers"):
		return true
	# The five map defense scenes currently share the generic demolition group;
	# accepting that group also keeps editor-authored/custom defense subclasses
	# discoverable without making the checkpoint depend on scene class names.
	return node.is_in_group(DEFENSE_MEMBER_GROUP) \
		or node.is_in_group("chain_link_fences") \
		or node.is_in_group("road_barriers") \
		or node is ChainLinkFence or node is RoadBarrier or node is MapDefenseFacility


func _resolve_member_root(node: Node) -> Node:
	var cursor := node
	var hops := 0
	while cursor != null and hops < 24:
		if _is_checkpoint_member(cursor):
			return cursor
		cursor = cursor.get_parent()
		hops += 1
	return null


func _member_id(member: Node) -> String:
	for meta_name in [
		"network_map_facility_id",
		"network_device_id",
		"map_editor_uuid",
		"road_blocker_id",
		"member_id",
		"network_id",
	]:
		var meta_value := str(member.get_meta(meta_name, "")).strip_edges()
		if not meta_value.is_empty():
			return meta_value
	for property_name in ["member_id", "network_id", "road_blocker_id"]:
		if not _has_property(member, property_name):
			continue
		var property_value := str(member.get(property_name)).strip_edges()
		if not property_value.is_empty():
			return property_value
	return str(member.get_path()) if member.is_inside_tree() else str(member.get_instance_id())


func _register_member(member: Node) -> void:
	if member == null or not is_instance_valid(member):
		return
	var member_id := _member_id(member)
	if member_id.is_empty():
		return
	if _members.has(member_id) and is_instance_valid(_members[member_id]):
		return
	_members[member_id] = member
	if member.is_in_group("road_blockers"):
		_blockers[member_id] = member
		# TODO(RoadBlockerAI):
		# Future RoadBlocker must expose:
		#   bind_checkpoint(checkpoint: RoadCheckpoint)
		#   set_checkpoint_attack_permission(enabled: bool, reason: StringName)
		#   get_network_state() -> Dictionary
		#   apply_network_state(state: Dictionary)
		#
		# The blocker scene must add itself to the "road_blockers" group.
		# RoadCheckpoint must not depend on a concrete RoadBlocker script yet.
		if _is_authority() and member.has_method("bind_checkpoint"):
			member.call("bind_checkpoint", self)
		if _is_authority() and member.has_method("set_checkpoint_attack_permission"):
			member.call(
				"set_checkpoint_attack_permission",
				alarm_active,
				StringName(alarm_reason if alarm_active else "member_registered")
			)
	else:
		if member is RoadBarrier:
			var barrier := member as RoadBarrier
			_barriers[member_id] = barrier
			barrier.set_checkpoint_managed(true)
			_barrier_occupants[member_id] = {}
			if barrier.has_method("get_test_enter_occupants"):
				for entrant in barrier.call("get_test_enter_occupants"):
					if entrant is Node:
						_barrier_occupants[member_id][entrant.get_instance_id()] = entrant
			_connect_barrier_signals(barrier, member_id)
		_connect_member_damage_signals(member, member_id)
	member_registered.emit(member)


func _connect_barrier_signals(barrier: RoadBarrier, member_id: String) -> void:
	var entered_callable := _on_barrier_entered.bind(member_id)
	var exited_callable := _on_barrier_exited.bind(member_id)
	if not _member_connections.has("barrier_entered:%s" % member_id):
		if not barrier.test_entered.is_connected(entered_callable):
			barrier.test_entered.connect(entered_callable)
		_member_connections["barrier_entered:%s" % member_id] = entered_callable
	if not _member_connections.has("barrier_exited:%s" % member_id):
		if not barrier.test_exited.is_connected(exited_callable):
			barrier.test_exited.connect(exited_callable)
		_member_connections["barrier_exited:%s" % member_id] = exited_callable


func _connect_member_damage_signals(member: Node, member_id: String) -> void:
	for signal_name in ["defense_destroyed", "defense_respawned"]:
		if not member.has_signal(signal_name):
			continue
		var connection_key := "%s:%s" % [signal_name, member_id]
		if _member_connections.has(connection_key):
			continue
		var callback := _on_member_destroyed.bind(member) if signal_name == "defense_destroyed" \
			else _on_member_respawned.bind(member)
		# Membership reconciliation can run while an editor/network identity is
		# being assigned, so the key may have changed although this exact Callable
		# is already connected.  Ask Godot as the source of truth before connect.
		if not member.is_connected(signal_name, callback):
			member.connect(signal_name, callback)
		_member_connections[connection_key] = callback


func _unregister_member(member_id: String) -> void:
	# Keep this untyped until validity is known; see _reconcile_membership().
	var member_value: Variant = _members.get(member_id, null)
	var damage_record: Dictionary = _member_damage.get(member_id, {}) as Dictionary
	var was_destroyed := bool(damage_record.get("destroyed", false))
	if is_instance_valid(member_value):
		was_destroyed = was_destroyed or _member_is_destroyed(member_value as Node)
	var member: Node = member_value as Node if is_instance_valid(member_value) else null
	_members.erase(member_id)
	_barriers.erase(member_id)
	var blocker_value: Variant = _blockers.get(member_id, null)
	var blocker: Node = blocker_value as Node if is_instance_valid(blocker_value) else null
	_blockers.erase(member_id)
	_barrier_occupants.erase(member_id)
	_member_damage.erase(member_id)
	# A non-respawning facility is queue-freed after the authority reports its
	# final player-owned hit. Keep that alarm source alive for the configured
	# timeout even though the node is no longer available to scan.
	if not was_destroyed:
		_alarm_sources.erase(member_id)
	for connection_key_value in _member_connections.keys():
		var connection_key := str(connection_key_value)
		if connection_key.ends_with(":%s" % member_id):
			var callback: Callable = _member_connections[connection_key_value]
			var signal_name := connection_key.get_slice(":", 0)
			# Disconnect before dropping the bookkeeping entry. Facilities can
			# leave and re-enter a checkpoint during map streaming; retaining the
			# old Callable would either leak the node or create duplicate signal
			# callbacks when it is registered again.
			if is_instance_valid(member) and member.has_signal(signal_name) \
				and member.is_connected(signal_name, callback):
				member.disconnect(signal_name, callback)
			_member_connections.erase(connection_key_value)
	if is_instance_valid(member):
		if member is RoadBarrier and member.has_method("set_checkpoint_managed"):
			member.call("set_checkpoint_managed", false)
		member_unregistered.emit(member)
	if is_instance_valid(blocker) and _is_authority() \
		and blocker.has_method("set_checkpoint_attack_permission"):
		blocker.call("set_checkpoint_attack_permission", false, StringName("member_removed"))
	if _alarm_sources.is_empty() and alarm_active:
		_clear_alarm("member_removed")


func _reconcile_occupants() -> void:
	if not is_inside_tree():
		return
	var current: Dictionary = {}
	for body in get_overlapping_bodies():
		var actor := _resolve_actor_root(body)
		if actor != null:
			current[_actor_id(actor)] = actor
	for area in get_overlapping_areas():
		var actor := _resolve_actor_root(area)
		if actor != null:
			current[_actor_id(actor)] = actor
	_occupants = current


func _resolve_actor_root(node: Node) -> Node:
	var cursor := node
	var hops := 0
	while cursor != null and hops < 24:
		if cursor is GamePlayer or cursor is VehicleBase \
			or cursor.is_in_group("human_players") or cursor.is_in_group("server_human_players") \
			or cursor.is_in_group("vehicles"):
			return cursor
		cursor = cursor.get_parent()
		hops += 1
	return null


func _actor_id(actor: Node) -> String:
	if actor is GamePlayer:
		return "player:%d" % int((actor as GamePlayer).authority_peer_id)
	if _has_property(actor, "authority_peer_id"):
		return "player:%d" % int(actor.get("authority_peer_id"))
	if actor is VehicleBase and actor.has_method("get_vehicle_id"):
		return "vehicle:%s" % str(actor.call("get_vehicle_id"))
	return str(actor.get_instance_id())


func _on_body_entered(body: Node3D) -> void:
	var actor := _resolve_actor_root(body)
	if actor != null:
		_occupants[_actor_id(actor)] = actor
	var member := _resolve_member_root(body)
	if member != null and _is_checkpoint_member(member):
		_register_member(member)


func _on_body_exited(body: Node3D) -> void:
	var actor := _resolve_actor_root(body)
	if actor != null:
		_occupants.erase(_actor_id(actor))


func _on_area_entered(area: Area3D) -> void:
	var actor := _resolve_actor_root(area)
	if actor != null:
		_occupants[_actor_id(actor)] = actor
	var member := _resolve_member_root(area)
	if member != null and _is_checkpoint_member(member):
		_register_member(member)


func _on_area_exited(area: Area3D) -> void:
	var actor := _resolve_actor_root(area)
	if actor != null:
		_occupants.erase(_actor_id(actor))


func _on_barrier_entered(entrant: Node, member_id: String) -> void:
	if not _barrier_occupants.has(member_id):
		_barrier_occupants[member_id] = {}
	if is_instance_valid(entrant):
		_barrier_occupants[member_id][entrant.get_instance_id()] = entrant
	_empty_barrier_elapsed = 0.0


func _on_barrier_exited(entrant: Node, member_id: String) -> void:
	if _barrier_occupants.has(member_id) and is_instance_valid(entrant):
		_barrier_occupants[member_id].erase(entrant.get_instance_id())


func _update_access_and_barriers(delta: float) -> void:
	# A destroyed barrier stops its TestEnterArea authority loop. Prune the
	# cached entrants here so a player who was standing in the old detection
	# volume cannot keep another barrier artificially open forever.
	for barrier_id_value in _barrier_occupants.keys():
		# A RoadBarrier may be freed by a collision/destruction callback before
		# membership reconciliation removes its cached entry.  Check the Variant
		# first; casting a freed Object wrapper itself emits a Godot error.
		var barrier_value: Variant = _barriers.get(str(barrier_id_value), null)
		var barrier: RoadBarrier = barrier_value as RoadBarrier if is_instance_valid(barrier_value) else null
		if not is_instance_valid(barrier) or barrier.destroyed or barrier.arm_destroyed:
			(_barrier_occupants[barrier_id_value] as Dictionary).clear()
			continue
		var occupants := _barrier_occupants[barrier_id_value] as Dictionary
		for entrant_id_value in occupants.keys():
			if not is_instance_valid(occupants[entrant_id_value]):
				occupants.erase(entrant_id_value)
	var allowed := false
	for actor_value in _occupants.values():
		var actor := actor_value as Node
		if is_instance_valid(actor) and _actor_has_access(actor):
			allowed = true
			break
	if not allowed:
		for occupants_value in _barrier_occupants.values():
			if not occupants_value is Dictionary:
				continue
			for entrant_value in (occupants_value as Dictionary).values():
				var entrant := entrant_value as Node
				if is_instance_valid(entrant) and _actor_has_access(entrant):
					allowed = true
					break
			if allowed:
				break
	if allowed != _last_access_allowed:
		_last_access_allowed = allowed
		access_state_changed.emit(allowed)
	if allowed:
		_empty_barrier_elapsed = 0.0
		for barrier_value in _barriers.values():
			if barrier_value is RoadBarrier and is_instance_valid(barrier_value):
				(barrier_value as RoadBarrier).raise_barrier()
		return
	var barrier_occupied := false
	for occupants_value in _barrier_occupants.values():
		if occupants_value is Dictionary and not (occupants_value as Dictionary).is_empty():
			barrier_occupied = true
			break
	if barrier_occupied:
		_empty_barrier_elapsed = 0.0
		return
	var any_raised := false
	for barrier_value in _barriers.values():
		if barrier_value is RoadBarrier and is_instance_valid(barrier_value):
			any_raised = any_raised or (barrier_value as RoadBarrier).is_barrier_raised()
	# A raised barrier must not lower while somebody is still inside the
	# checkpoint's through-lane.  TestEnterArea signals cover the immediate
	# barrier approach, while the checkpoint Area itself represents the full
	# corridor and catches occupants between multiple barriers.
	var corridor_occupied := false
	for actor_value in _occupants.values():
		if is_instance_valid(actor_value) and actor_value is Node:
			corridor_occupied = true
			break
	if corridor_occupied:
		_empty_barrier_elapsed = 0.0
		return
	if any_raised:
		_empty_barrier_elapsed += delta
		if _empty_barrier_elapsed >= maxf(0.0, barrier_lower_delay_seconds):
			for barrier_value in _barriers.values():
				if barrier_value is RoadBarrier and is_instance_valid(barrier_value):
					(barrier_value as RoadBarrier).lower_barrier()
			_empty_barrier_elapsed = 0.0
	else:
		_empty_barrier_elapsed = 0.0


func _actor_has_access(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var team := _actor_team(actor)
	if not team.is_empty() and _team_has_card(team):
		return true
	# Keep the live node as a same-frame fallback for local/test players. The
	# authoritative GameAuthority query remains the normal path, but a newly
	# granted card may not have reached player_states until the next interaction
	# sync.
	if _actor_has_personal_card(actor):
		return true
	if actor is GamePlayer:
		return _player_has_card(int((actor as GamePlayer).authority_peer_id))
	if _has_property(actor, "authority_peer_id"):
		return _player_has_card(int(actor.get("authority_peer_id")))
	if actor is VehicleBase or actor.is_in_group("vehicles"):
		var driver_peer := int(actor.get("driver_peer_id")) if _has_property(actor, "driver_peer_id") else 0
		if driver_peer > 0 and _player_has_card(driver_peer):
			return true
		if actor.has_method("get_seat_occupants"):
			var seat_peers: Variant = actor.call("get_seat_occupants")
			if seat_peers is Array:
				for peer_value: Variant in seat_peers:
					if peer_value is Node:
						if _actor_has_personal_card(peer_value as Node):
							return true
					elif int(peer_value) > 0 and _player_has_card(int(peer_value)):
						return true
		if _has_property(actor, "seat_occupants"):
			var raw_occupants: Variant = actor.get("seat_occupants")
			if raw_occupants is Dictionary:
				for occupant_value: Variant in (raw_occupants as Dictionary).values():
					if occupant_value is Node and _actor_has_personal_card(occupant_value as Node):
						return true
					elif (occupant_value is int or occupant_value is float or occupant_value is String) \
						and int(occupant_value) > 0 and _player_has_card(int(occupant_value)):
						return true
		var vehicle_id := str(actor.call("get_vehicle_id")) if actor.has_method("get_vehicle_id") else ""
		if not vehicle_id.is_empty() and is_instance_valid(GameAuthority):
			for peer_value in GameAuthority.player_states.keys():
				var peer_id := int(peer_value)
				var state: Dictionary = GameAuthority.player_states.get(peer_value, {}) as Dictionary
				if str(state.get("vehicle_id", "")) == vehicle_id and _player_has_card(peer_id):
					return true
	return false


func _actor_has_personal_card(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	for property_name in ["backpack_items", "backpack_slot_items", "inventory"]:
		if not _has_property(actor, property_name):
			continue
		if _inventory_value_has_card(actor.get(property_name)):
			return true
	return false


func _inventory_value_has_card(value: Variant) -> bool:
	if value is String:
		return str(value) == access_card_id
	if value is Array:
		for entry_value: Variant in value:
			if _inventory_value_has_card(entry_value):
				return true
		return false
	if not value is Dictionary:
		return false
	var item := value as Dictionary
	var direct_quantity: Variant = item.get(access_card_id, 0.0)
	if direct_quantity is int or direct_quantity is float:
		if float(direct_quantity) > 0.0:
			return true
	if direct_quantity is String and float(direct_quantity) > 0.0:
		return true
	var item_id := str(item.get("item_id", item.get("card_id", item.get("tool_id", ""))))
	if item_id == access_card_id:
		return true
	# Dictionary inventories often map item ids to quantities instead of using
	# the key_item record shape.
	for key_value: Variant in item.keys():
		var quantity: Variant = item[key_value]
		if str(key_value) == access_card_id:
			if (quantity is int or quantity is float) and float(quantity) > 0.0:
				return true
			if quantity is String and float(quantity) > 0.0:
				return true
		# Some inventory adapters wrap slot records under an "items" or
		# "entries" key. Walk nested containers so a key_item record is still
		# recognized without coupling the checkpoint to one inventory layout.
		if quantity is Array or quantity is Dictionary:
			if _inventory_value_has_card(quantity):
				return true
	return false


func _allowed_team(team: String) -> bool:
	var normalized := team.strip_edges().to_lower()
	if normalized.is_empty():
		return false
	for allowed_value: String in allowed_team_ids:
		if str(allowed_value).strip_edges().to_lower() == normalized:
			return true
	return false


func _actor_team(actor: Node) -> String:
	if actor is GamePlayer:
		return str((actor as GamePlayer).team).to_lower()
	if actor.has_method("get_combat_team"):
		return str(actor.call("get_combat_team")).to_lower()
	if _has_property(actor, "team"):
		return str(actor.get("team")).to_lower()
	if _has_property(actor, "team_id"):
		return str(actor.get("team_id")).to_lower()
	if actor is VehicleBase or actor.is_in_group("vehicles"):
		if is_instance_valid(GameAuthority) and GameAuthority.has_method("_vehicle_team"):
			if actor is VehicleBase:
				return str(GameAuthority.call("_vehicle_team", actor)).to_lower()
		var owner_team := str(actor.get("owner_team")).to_lower() \
			if _has_property(actor, "owner_team") else ""
		if not owner_team.is_empty():
			return owner_team
		var driver_peer := int(actor.get("driver_peer_id")) \
			if _has_property(actor, "driver_peer_id") else 0
		if driver_peer > 0 and is_instance_valid(GameAuthority):
			var state: Dictionary = GameAuthority.player_states.get(driver_peer, {}) as Dictionary
			return str(state.get("team", "")).to_lower()
	return ""


func _player_has_card(peer_id: int) -> bool:
	if peer_id <= 0 or not is_instance_valid(GameAuthority):
		return false
	if GameAuthority.has_method("player_has_access_card"):
		return bool(GameAuthority.call("player_has_access_card", peer_id, access_card_id))
	return false


func _team_has_card(team: String) -> bool:
	return not team.is_empty() and is_instance_valid(GlobalVar) \
		and GlobalVar.check_team_item_amount(team, access_card_id) > 0.0


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for info in object.get_property_list():
		if str((info as Dictionary).get("name", "")) == property_name:
			return true
	return false


func _on_member_destroyed(member: Node) -> void:
	if not _is_authority() or not is_instance_valid(member):
		return
	var member_id := _member_id(member)
	# The signal does not carry attacker provenance. Marking the member as
	# destroyed here is useful for diagnostics, but the alarm is raised only
	# after GameAuthority reports a player-owned authoritative damage event.
	var record: Dictionary = _member_damage.get(member_id, {"damage": 0.0, "destroyed": false})
	record["destroyed"] = true
	_member_damage[member_id] = record


func _on_member_respawned(member: Node) -> void:
	if not _is_authority() or not is_instance_valid(member):
		return
	var member_id := _registered_member_id(member)
	if member_id.is_empty():
		member_id = _member_id(member)
	_member_damage.erase(member_id)
	_alarm_sources.erase(member_id)
	if _alarm_sources.is_empty() and alarm_active:
		_clear_alarm("facility_respawned")


func _notify_member_damage(member: Node, applied_damage: float, source_context: Dictionary) -> void:
	if not _is_authority() or member == null or not is_instance_valid(member):
		return
	var damage_member: Node = member
	var resolved_member_id := _registered_member_id(member)
	if resolved_member_id.is_empty():
		var resolved_root := _resolve_member_root(member)
		if resolved_root != null:
			damage_member = resolved_root
			resolved_member_id = _registered_member_id(resolved_root)
	if resolved_member_id.is_empty():
		return
	if not bool(source_context.get("player_owned", false)):
		return
	var member_id := resolved_member_id
	var event_id := str(source_context.get("damage_event_id", "")).strip_edges()
	if not event_id.is_empty():
		# One explosion may damage multiple facilities in the same checkpoint;
		# deduplicate by event *and member* so a replay cannot double-count one
		# facility without suppressing legitimate damage to its neighbour.
		var member_event_key := "%s:%s" % [event_id, member_id]
		if _processed_damage_event_ids.has(member_event_key):
			return
		_processed_damage_event_ids[member_event_key] = true
		if _processed_damage_event_ids.size() > 1024:
			_processed_damage_event_ids.erase(_processed_damage_event_ids.keys()[0])
	var record: Dictionary = _member_damage.get(member_id, {"damage": 0.0, "destroyed": false})
	if applied_damage > 0.0:
		record["damage"] = float(record.get("damage", 0.0)) + applied_damage
	if bool(source_context.get("destroyed", false)) or _member_is_destroyed(damage_member):
		record["destroyed"] = true
	_member_damage[member_id] = record
	if bool(record.get("destroyed", false)) or float(record.get("damage", 0.0)) > maxf(0.0, damage_alarm_threshold):
		_trigger_alarm("facility:%s" % member_id, member_id, source_context)


func _member_is_destroyed(member: Node) -> bool:
	if _has_property(member, "destroyed") and bool(member.get("destroyed")):
		return true
	if _has_property(member, "current_hp") and float(member.get("current_hp")) <= 0.0:
		return true
	if member is RoadBarrier:
		return (member as RoadBarrier).arm_destroyed
	return false


func notify_member_damage(member: Node, applied_damage: float, source_context: Dictionary = {}) -> void:
	## Public authority hook used by GameAuthority after HP is actually reduced.
	_notify_member_damage(member, applied_damage, source_context)


func notify_blocker_attacked(blocker: Node, source_context: Dictionary = {}) -> void:
	## Future Blocker hit events intentionally bypass the facility threshold.
	if not _is_authority() or blocker == null or not is_instance_valid(blocker) \
		or not blocker.is_in_group("road_blockers"):
		return
	if _registered_member_id(blocker).is_empty():
		return
	if not bool(source_context.get("player_owned", false)):
		return
	var event_id := str(source_context.get("damage_event_id", "")).strip_edges()
	if not event_id.is_empty():
		if _processed_damage_event_ids.has("blocker:%s" % event_id):
			return
		_processed_damage_event_ids["blocker:%s" % event_id] = true
	_alarm_sources["blocker_attack"] = true
	_trigger_alarm("blocker_attack", "blocker_attack", source_context)


func _registered_member_id(member: Node) -> String:
	if member == null or not is_instance_valid(member):
		return ""
	var member_id := _member_id(member)
	if _members.has(member_id):
		return member_id
	for existing_id_value in _members.keys():
		if _members[existing_id_value] == member:
			return str(existing_id_value)
	return ""


func _trigger_alarm(reason: String, source_id := "", source_context: Dictionary = {}) -> void:
	if not _is_authority():
		return
	if not source_id.is_empty():
		_alarm_sources[source_id] = true
	alarm_active = true
	alarm_reason = reason
	alarm_remaining = maxf(0.0, alarm_timeout_seconds)
	for blocker_value in _blockers.values():
		var blocker := blocker_value as Node
		if is_instance_valid(blocker) and blocker.has_method("set_checkpoint_attack_team"):
			blocker.call("set_checkpoint_attack_team", str(source_context.get("attacker_team", "")))
		if is_instance_valid(blocker) and blocker.has_method("set_checkpoint_attack_permission"):
			blocker.call("set_checkpoint_attack_permission", true, StringName(reason))
	alarm_changed.emit(true, reason)
	_emit_network_state()


func _clear_alarm(reason: String) -> void:
	if not _is_authority():
		return
	if not alarm_active:
		_alarm_sources.clear()
		return
	alarm_active = false
	alarm_reason = reason
	alarm_remaining = 0.0
	_alarm_sources.clear()
	for blocker_value in _blockers.values():
		var blocker := blocker_value as Node
		if is_instance_valid(blocker) and blocker.has_method("set_checkpoint_attack_permission"):
			blocker.call("set_checkpoint_attack_permission", false, StringName(reason))
	alarm_changed.emit(false, reason)
	_emit_network_state()


func get_network_state() -> Dictionary:
	var barrier_states: Array[Dictionary] = []
	for member_id_value in _barriers.keys():
		var barrier := _barriers[member_id_value] as Node
		if not is_instance_valid(barrier) or not barrier.has_method("get_network_state"):
			continue
		barrier_states.append({
			"member_id": str(member_id_value),
			"state": barrier.call("get_network_state"),
		})
	return {
		"checkpoint_id": checkpoint_id,
		"alarm_active": alarm_active,
		"alarm_reason": alarm_reason,
		"alarm_remaining": alarm_remaining,
		"barrier_raised": _any_barrier_raised(),
		"barriers": barrier_states,
	}


func apply_network_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	var previous_alarm_active := alarm_active
	var previous_alarm_reason := alarm_reason
	_pending_network_state = state.duplicate(true)
	checkpoint_id = str(state.get("checkpoint_id", checkpoint_id))
	alarm_active = bool(state.get("alarm_active", alarm_active))
	alarm_reason = str(state.get("alarm_reason", alarm_reason))
	alarm_remaining = maxf(0.0, float(state.get("alarm_remaining", alarm_remaining)))
	var barriers_value: Variant = state.get("barriers", [])
	var unresolved_barrier_state := false
	var applied_barrier_entry := false
	if barriers_value is Array:
		for entry_value in barriers_value:
			if not entry_value is Dictionary:
				continue
			var entry := entry_value as Dictionary
			var barrier := _barriers.get(str(entry.get("member_id", "")), null) as Node
			var barrier_state: Variant = entry.get("state", {})
			if is_instance_valid(barrier) and barrier_state is Dictionary and barrier.has_method("apply_network_state"):
				barrier.call("apply_network_state", barrier_state as Dictionary)
				applied_barrier_entry = true
			else:
				unresolved_barrier_state = true
	# Older/compact snapshots may only carry one aggregate raised flag. Apply it
	# as a fallback while retaining the pending snapshot until membership exists.
	if not applied_barrier_entry and state.has("barrier_raised"):
		var raised := bool(state.get("barrier_raised", false))
		if _barriers.is_empty() and raised:
			unresolved_barrier_state = true
		else:
			for barrier_value in _barriers.values():
				if barrier_value is RoadBarrier and is_instance_valid(barrier_value):
					(barrier_value as RoadBarrier).set_barrier_raised(raised, false)
	if not unresolved_barrier_state:
		_pending_network_state.clear()
	if previous_alarm_active != alarm_active or previous_alarm_reason != alarm_reason:
		alarm_changed.emit(alarm_active, alarm_reason)


func _apply_pending_network_state() -> void:
	var state := _pending_network_state.duplicate(true)
	_pending_network_state.clear()
	apply_network_state(state)


func _any_barrier_raised() -> bool:
	for barrier_value in _barriers.values():
		if barrier_value is RoadBarrier and is_instance_valid(barrier_value) \
			and (barrier_value as RoadBarrier).is_barrier_raised():
			return true
	return false


func get_registered_members() -> Array[Node]:
	var result: Array[Node] = []
	for member_value in _members.values():
		if is_instance_valid(member_value) and member_value is Node:
			result.append(member_value as Node)
	return result


func get_registered_barriers() -> Array[Node]:
	var result: Array[Node] = []
	for barrier_value in _barriers.values():
		if is_instance_valid(barrier_value) and barrier_value is Node:
			result.append(barrier_value as Node)
	return result


func get_registered_blockers() -> Array[Node]:
	var result: Array[Node] = []
	for blocker_value in _blockers.values():
		if is_instance_valid(blocker_value) and blocker_value is Node:
			result.append(blocker_value as Node)
	return result


func get_member_damage(member: Node) -> float:
	if member == null:
		return 0.0
	var member_id := _registered_member_id(member)
	if member_id.is_empty():
		member_id = _member_id(member)
	return float((_member_damage.get(member_id, {}) as Dictionary).get("damage", 0.0))


func _emit_network_state() -> void:
	if not _is_authority() or not is_instance_valid(GameAuthority):
		return
	if GameAuthority.has_signal("reliable_world_event_ready"):
		GameAuthority.reliable_world_event_ready.emit({
			"type": "road_checkpoint_state",
			"checkpoint_id": checkpoint_id,
			"state": get_network_state(),
			"tick": int(GameAuthority.get("server_tick")) if _has_property(GameAuthority, "server_tick") else 0,
		})
