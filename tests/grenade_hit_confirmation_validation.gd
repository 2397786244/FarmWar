extends Node3D

const PLAYER_SCENE := preload("res://character/player.tscn")
const ZOMBIE_SCENE := preload("res://character/Zombie.tscn")
const BLACK_BEAR_SCENE := preload("res://items/BlackBear.tscn")
const WRECK_AI_SCENE := preload("res://character/WreckAI.tscn")
const GRENADE_SCENE := preload("res://character/weapons/Grenade.tscn")

const ATTACKER_PEER_ID := 1
const PROJECTILE_ID := 93001
const TRACE_PROJECTILE_ID := 93002

var failures := 0
var hit_confirmations: Array[Dictionary] = []
var presentation_player: GamePlayer


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode({
		"display_name": "GrenadeHitConfirmationValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = self
	await _validate_grenade_tracer_start()
	if not GameAuthority.reliable_world_event_ready.is_connected(_capture_reliable_event):
		GameAuthority.reliable_world_event_ready.connect(_capture_reliable_event)

	presentation_player = PLAYER_SCENE.instantiate() as GamePlayer
	_check(presentation_player != null, "player scene instantiates for grenade hit marker validation")
	if presentation_player == null:
		_finish()
		return
	presentation_player.authority_peer_id = ATTACKER_PEER_ID
	presentation_player.team = "red"
	add_child(presentation_player)

	var zombie := ZOMBIE_SCENE.instantiate() as Zombie
	var bear := BLACK_BEAR_SCENE.instantiate() as BlackBear
	_check(zombie != null and bear != null, "zombie and BlackBear scenes instantiate")
	if zombie == null or bear == null:
		_finish()
		return
	zombie.position = Vector3(0.0, 0.0, -2.0)
	bear.position = Vector3(0.0, 0.0, 2.0)
	add_child(zombie)
	add_child(bear)
	var wreck_ai := WRECK_AI_SCENE.instantiate() as AIPlayer
	_check(wreck_ai != null, "legacy WreckAI scene instantiates")
	if wreck_ai == null:
		_finish()
		return
	wreck_ai.team_id = "blue"
	wreck_ai.position = Vector3(-4.0, 0.0, 0.0)
	add_child(wreck_ai)
	await get_tree().process_frame
	zombie.set_physics_process(false)
	bear.set_physics_process(false)
	wreck_ai.set_physics_process(false)
	var zombie_hit_area := zombie.get_node_or_null("Hit3D") as Area3D
	_check(zombie_hit_area != null, "zombie body hit area is available for component dispatch")
	if zombie_hit_area != null:
		# Hit3D reaches Zombie through the generic damageable-component lookup.
		# This must use Zombie's six-argument signature; RoadBarrier-style
		# components are the ones that additionally consume shape_index.
		zombie.current_hp = 2.0
		var routed_zombie_hit := bool(GameAuthority.call(
			"_apply_hit_to_collider",
			zombie_hit_area,
			"nail",
			1.0,
			"red",
			-1,
			ATTACKER_PEER_ID,
			presentation_player
		))
		_check(routed_zombie_hit, "zombie child collider uses its six-argument hit dispatch")
		_check(is_equal_approx(zombie.current_hp, 1.0), "zombie body hit applies damage after dispatch")
	zombie.current_hp = 1.0
	bear.current_hp = 1.0
	wreck_ai.current_hp = 1.0
	presentation_player.current_tool_index = -1
	hit_confirmations.clear()
	GameAuthority.projectile_states[PROJECTILE_ID] = {
		"type": "grenade",
		"team": "red",
		"owner_peer_id": ATTACKER_PEER_ID,
		"radius": 6.0,
		"damage": 100.0,
		"knockback": 0.0,
		"effect": "grenade",
		"show_owner_hit_marker": true,
		"friendly_fire": true,
		"linear_falloff": true,
	}
	GameAuthority.call("_explode_projectile", PROJECTILE_ID, Vector3.ZERO, 0, true)
	_check(zombie.destroyed, "grenade explosion kills the zombie through the authority path")
	_check(bear.destroyed, "grenade explosion kills BlackBear through the authority path")
	_check(wreck_ai.state == AIPlayer.AIState.DEAD, "grenade explosion damages WreckAI through the authority path")
	_check(hit_confirmations.size() == 1, "grenade explosion emits one aggregated hit confirmation")
	if not hit_confirmations.is_empty():
		_check(
			int(hit_confirmations[0].get("attacker_peer_id", 0)) == ATTACKER_PEER_ID
				and int(hit_confirmations[0].get("target_count", 0)) == 3
				and str(hit_confirmations[0].get("source", "")) == "grenade",
			"grenade confirmation contains all damaged targets and the throwing peer"
		)
	presentation_player.call("_update_crosshair_visibility")
	_check(
		presentation_player.hit_marker.visible,
		"grenade hit marker stays visible after its consumed throwable is unequipped"
	)
	_finish()


func _validate_grenade_tracer_start() -> void:
	var grenade := GRENADE_SCENE.instantiate() as Node3D
	_check(grenade != null, "grenade scene instantiates with its trace")
	if grenade == null:
		return
	add_child(grenade)
	await get_tree().process_frame
	var trace := grenade.get_node_or_null("Trace") as BulletTracerSegment
	_check(trace != null, "grenade Trace uses the bullet tracer effect")
	if trace != null:
		_check(not trace.visible and not trace.tracing_enabled, "held grenade Trace starts hidden and disabled")
		trace.start_tracing()
		grenade.global_position = Vector3(0.0, 1.0, 0.0)
		trace.refresh_visual()
		_check(trace.visible, "grenade Trace starts when the thrown grenade moves")
		trace.stop_tracing()
		_check(not trace.visible and not trace.tracing_enabled, "grenade Trace hides when tracing stops")
	grenade.queue_free()

	GameAuthority.call("_spawn_local_projectile_visual", TRACE_PROJECTILE_ID, GRENADE_SCENE, {
		"type": "grenade",
		"position": Vector3.ZERO,
	})
	var visual_value: Variant = GameAuthority.local_projectile_visual_nodes.get(TRACE_PROJECTILE_ID, null)
	var authoritative_visual := visual_value as Node3D
	var authoritative_trace := authoritative_visual.get_node_or_null("Trace") as BulletTracerSegment \
		if authoritative_visual != null else null
	_check(
		authoritative_trace != null and authoritative_trace.frame_counter >= 2,
		"authority grenade spawn arms the Trace"
	)
	if authoritative_visual != null and authoritative_trace != null:
		authoritative_visual.global_position = Vector3(0.0, 1.0, 0.0)
		authoritative_trace.refresh_visual()
		_check(authoritative_trace.visible, "authority grenade Trace renders after movement")
		GameAuthority.projectile_states[TRACE_PROJECTILE_ID] = {
			"projectile_id": TRACE_PROJECTILE_ID,
			"type": "grenade",
			"position": authoritative_visual.global_position,
			"velocity": Vector3.ZERO,
			"gravity": 0.0,
			"collision_mask": 0,
			"fuse_only": true,
			"life": 0.0,
			"max_life": 5.0,
			"resting": true,
		}
		GameAuthority.call("_simulate_projectiles", 0.05)
		_check(not authoritative_trace.visible, "landed grenade hides the Trace")
		GameAuthority.projectile_states.erase(TRACE_PROJECTILE_ID)
	GameAuthority.call("_remove_local_projectile_visual", TRACE_PROJECTILE_ID)


func _capture_reliable_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "hit_confirmed":
		hit_confirmations.append(event.duplicate(true))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[GrenadeHitConfirmationValidation] PASS " + label)
	else:
		failures += 1
		push_error("[GrenadeHitConfirmationValidation] FAIL " + label)


func _finish() -> void:
	GameAuthority.projectile_states.erase(PROJECTILE_ID)
	GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)
