extends Node3D

const LONG_SPEAR_SCENE := preload("res://character/weapons/LongSpear.tscn")
const PLAYER_SCENE := preload("res://character/player.tscn")
const WARRIOR_SCENE := preload("res://character/FutureWarriorAI.tscn")
const BRICK_SCENE := preload("res://character/weapons/Brick.tscn")
const TREE_SCENE := preload("res://buildings/nature/CottonWood.tscn")

const ATTACKER_PEER_ID := 1
const TARGET_PEER_ID := 2
const ATTACKER_POSITION := Vector3.ZERO
const TIP_CENTER := Vector3(0.0, 1.2, -1.35)
const FAR_POSITION := Vector3(20.0, 0.0, 20.0)

var failures := 0
var hit_confirmations: Array[Dictionary] = []


class DamageDummy extends StaticBody3D:
	var current_hp := 100.0
	var combat_team := "blue"


	func configure() -> void:
		collision_layer = 128
		collision_mask = 0
		_add_shape(self, Vector3.ZERO)
		# Two independently queryable child areas exercise target de-duplication.
		for offset in [Vector3(-0.025, 0.0, 0.0), Vector3(0.025, 0.0, 0.0)]:
			var hit_area := Area3D.new()
			hit_area.collision_layer = 128
			hit_area.collision_mask = 0
			add_child(hit_area)
			_add_shape(hit_area, offset)


	func impact(_effect: String, damage: float, attacker_team: String = "") -> bool:
		if damage <= 0.0 or (not attacker_team.is_empty() and attacker_team == combat_team):
			return false
		current_hp = maxf(0.0, current_hp - damage)
		return true


	func _add_shape(parent: Node, offset: Vector3) -> void:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.18, 0.18, 0.18)
		collision.shape = shape
		collision.position = offset
		parent.add_child(collision)


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_scene_and_configuration()
	await _validate_passive_tip_approach()
	GameAuthority.start_local_mode({
		"display_name": "SpearAttacker",
		"team": "red",
		"primary_weapon_ids": ["long_spear"],
		"special_tool_ids": [],
		"current_tool_index": 0,
		"current_tool_id": "long_spear",
		"position": ATTACKER_POSITION,
	})
	if not GameAuthority.reliable_world_event_ready.is_connected(_capture_reliable_event):
		GameAuthority.reliable_world_event_ready.connect(_capture_reliable_event)
	# Drive authority calls explicitly in this isolated test. This keeps player
	# proxies stationary without disabling their CollisionObject participation.
	GameAuthority.set_physics_process(false)
	GameAuthority.register_or_update_player(TARGET_PEER_ID, {
		"display_name": "SpearTarget",
		"team": "blue",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
		"position": Vector3(0.0, 0.0, TIP_CENTER.z),
	})
	var presentation_player := PLAYER_SCENE.instantiate() as GamePlayer
	presentation_player.authority_peer_id = ATTACKER_PEER_ID
	presentation_player.team = "red"
	add_child(presentation_player)
	await get_tree().process_frame
	presentation_player.global_position = ATTACKER_POSITION
	presentation_player.set_physics_process(false)
	_check(is_instance_valid(presentation_player.hit_marker), "local player creates a hit marker UI")
	var attacker_proxy := GameAuthority.call(
		"_ensure_player_physics_node", ATTACKER_PEER_ID, ATTACKER_POSITION
	) as CharacterBody3D
	var target_proxy := GameAuthority.call(
		"_ensure_player_physics_node", TARGET_PEER_ID, Vector3(0.0, 0.0, TIP_CENTER.z)
	) as CharacterBody3D
	_check(attacker_proxy != null and target_proxy != null, "authority player proxies are available")

	var warrior := WARRIOR_SCENE.instantiate() as FutureWarriorAI
	warrior.team_id = "blue"
	warrior.server_authoritative = false
	add_child(warrior)
	warrior.global_position = Vector3(0.0, 0.0, TIP_CENTER.z)
	warrior.set_process(false)
	warrior.set_physics_process(false)

	var brick := BRICK_SCENE.instantiate() as BrickTool
	brick.tool_owner = "blue"
	add_child(brick)
	brick.activate_tool()
	brick.global_position = Vector3(0.0, 0.0, TIP_CENTER.z)

	var tree := TREE_SCENE.instantiate() as HarvestTree
	add_child(tree)
	tree.global_position = Vector3(0.0, 0.0, TIP_CENTER.z)

	var dummy := DamageDummy.new()
	dummy.configure()
	add_child(dummy)
	dummy.global_position = TIP_CENTER
	await get_tree().physics_frame
	await get_tree().physics_frame

	var first_result := GameAuthority.local_try_use_tool(
		ATTACKER_PEER_ID, _attack_request(TIP_CENTER)
	)
	_check(bool(first_result.get("ok", false)), "authority accepts a valid spear attack")
	_check(int(first_result.get("target_count", 0)) == 5, "one attack damages five distinct targets")
	_check(hit_confirmations.size() == 1 \
			and str(hit_confirmations[0].get("source", "")) == "long_spear" \
			and int(hit_confirmations[0].get("attacker_peer_id", 0)) == ATTACKER_PEER_ID,
		"spear hit emits the existing hit confirmation event for its attacker")
	await get_tree().process_frame
	_check(presentation_player.hit_marker.visible,
		"single-player spear hit keeps the existing hit marker visible after a frame")
	_check(is_equal_approx(float(GameAuthority.player_states[TARGET_PEER_ID].get("hp", 0.0)), 180.0),
		"enemy player takes exactly 20 damage")
	_check(is_equal_approx(warrior.current_hp, 180.0), "FutureWarrior takes exactly 20 damage")
	_check(is_equal_approx(brick.current_hp, 980.0), "damageable tool takes exactly 20 damage")
	_check(is_equal_approx(tree.current_hp, 480.0), "real harvest tree takes exactly 20 damage")
	_check(is_equal_approx(dummy.current_hp, 80.0),
		"target with multiple colliders takes only one 20 damage hit")

	# Remaining inside the tip box must not deal continuous Area3D damage.
	var passive_hp := dummy.current_hp
	for _frame in range(3):
		await get_tree().physics_frame
	_check(is_equal_approx(dummy.current_hp, passive_hp), "overlap without an attack causes no damage")

	# The same real target types must respect their existing friendly-fire rules.
	_set_target_player_team("red")
	warrior.team_id = "red"
	brick.tool_owner = "red"
	dummy.combat_team = "red"
	tree.global_position = FAR_POSITION
	var friendly_player_hp := float(GameAuthority.player_states[TARGET_PEER_ID].get("hp", 0.0))
	var friendly_warrior_hp := warrior.current_hp
	var friendly_brick_hp := brick.current_hp
	var friendly_dummy_hp := dummy.current_hp
	await get_tree().physics_frame
	var friendly_result := _direct_attack(TIP_CENTER)
	_check(int(friendly_result.get("target_count", 0)) == 0, "friendly targets are rejected")
	_check(is_equal_approx(float(GameAuthority.player_states[TARGET_PEER_ID].get("hp", 0.0)), friendly_player_hp),
		"friendly player is not damaged")
	_check(is_equal_approx(warrior.current_hp, friendly_warrior_hp), "friendly AI is not damaged")
	_check(is_equal_approx(brick.current_hp, friendly_brick_hp), "friendly tool is not damaged")
	_check(is_equal_approx(dummy.current_hp, friendly_dummy_hp), "friendly generic target is not damaged")

	# server_try_use_tool owns the one-second authoritative cooldown.
	_move_standard_targets_far(warrior, brick, target_proxy)
	dummy.global_position = TIP_CENTER
	dummy.combat_team = "blue"
	dummy.current_hp = 100.0
	_reset_attacker_cooldown()
	await get_tree().physics_frame
	var accepted := GameAuthority.server_try_use_tool(ATTACKER_PEER_ID, _attack_request(TIP_CENTER))
	var rejected := GameAuthority.server_try_use_tool(ATTACKER_PEER_ID, _attack_request(TIP_CENTER))
	_check(bool(accepted.get("ok", false)), "first attack starts the cooldown")
	_check(not bool(rejected.get("ok", false)) and str(rejected.get("reason", "")) == "cooldown",
		"second attack inside one second is rejected")
	_check(is_equal_approx(dummy.current_hp, 80.0), "cooldown prevents duplicate damage")

	# A forged distant tip falls back to the authority reach and cannot hit far away.
	dummy.current_hp = 100.0
	dummy.global_position = Vector3(0.0, 1.2, -10.0)
	await get_tree().physics_frame
	var far_result := _direct_attack(dummy.global_position)
	_check(int(far_result.get("target_count", 0)) == 0 and is_equal_approx(dummy.current_hp, 100.0),
		"out-of-range tip position cannot damage a distant target")

	# Opaque world geometry blocks the complete tip query.
	dummy.global_position = TIP_CENTER
	var wall := _create_wall()
	await get_tree().physics_frame
	var blocked_result := _direct_attack(TIP_CENTER)
	_check(bool(blocked_result.get("blocked", false)), "wall blocks spear authority query")
	_check(is_equal_approx(dummy.current_hp, 100.0), "target behind wall is not damaged")
	wall.queue_free()

	if failures == 0:
		print("[LongSpearCombatValidation] PASS all checks")
	else:
		push_error("[LongSpearCombatValidation] FAIL count=%d" % failures)
	GameAuthority.stop_authority()
	GameAuthority.set_physics_process(true)
	get_tree().quit(0 if failures == 0 else 1)


func _validate_passive_tip_approach() -> void:
	var spear := LONG_SPEAR_SCENE.instantiate() as Node3D
	add_child(spear)
	var attack_area := spear.find_child("AttackArea", true, false) as Area3D
	var approaching_target := DamageDummy.new()
	approaching_target.configure()
	add_child(approaching_target)
	approaching_target.global_position = FAR_POSITION
	await get_tree().physics_frame
	var hp_before_approach := approaching_target.current_hp
	# Move an attackable body onto the real authored spear tip without issuing
	# use_tool or calling the authority melee endpoint.
	approaching_target.global_position = attack_area.global_position
	for _frame in range(8):
		await get_tree().physics_frame
	_check(is_equal_approx(approaching_target.current_hp, hp_before_approach),
		"target approaching and resting on idle spear tip takes no damage")
	approaching_target.queue_free()
	spear.queue_free()
	await get_tree().physics_frame


func _validate_scene_and_configuration() -> void:
	var spear := LONG_SPEAR_SCENE.instantiate() as Node3D
	_check(spear != null, "LongSpear scene loads")
	if spear == null:
		return
	add_child(spear)
	var attack_area := spear.find_child("AttackArea", true, false) as Area3D
	var collision := attack_area.find_child("CollisionShape3D", true, false) as CollisionShape3D \
			if attack_area != null else null
	_check(attack_area != null, "AttackArea is found recursively")
	_check(collision != null and collision.shape is BoxShape3D, "AttackArea has a BoxShape3D")
	if collision != null and collision.shape is BoxShape3D:
		_check((collision.shape as BoxShape3D).size.is_equal_approx(Vector3(0.2, 0.2, 0.3)),
			"AttackArea shape matches authority dimensions")
	_check(not attack_area.monitoring and not attack_area.monitorable,
		"AttackArea cannot apply continuous client-side damage")
	_check(is_equal_approx(CombatBalance.get_float("long_spear", "damage"), 20.0),
		"LongSpear damage is 20")
	var definition: Dictionary = GameAuthority.authoritative_tool_definitions.get("long_spear", {})
	_check(str(definition.get("category", "")) == "melee", "LongSpear is configured as melee")
	_check(is_equal_approx(float(definition.get("cooldown", 0.0)), 1.0), "LongSpear cooldown is one second")
	_check(not bool(definition.get("two_handed", true)), "LongSpear is single-handed")
	_check(not definition.has("magazine_size"), "LongSpear has no ammunition state")
	spear.queue_free()


func _direct_attack(center: Vector3) -> Dictionary:
	return GameAuthority.call("_server_long_spear", ATTACKER_PEER_ID, _attack_request(center)) as Dictionary


func _attack_request(center: Vector3) -> Dictionary:
	return {
		"tool_id": "long_spear",
		"tool_index": 0,
		"melee_center": center,
		"origin": ATTACKER_POSITION + Vector3.UP * 1.2,
		"direction": Vector3.FORWARD,
		"player_position": ATTACKER_POSITION,
		"yaw": 0.0,
		"pitch": 0.0,
	}


func _set_target_player_team(team: String) -> void:
	var state: Dictionary = GameAuthority.player_states[TARGET_PEER_ID]
	state["team"] = team
	GameAuthority.player_states[TARGET_PEER_ID] = state


func _reset_attacker_cooldown() -> void:
	var state: Dictionary = GameAuthority.player_states[ATTACKER_PEER_ID]
	var cooldowns: Dictionary = state.get("tool_cooldowns", {})
	cooldowns["long_spear"] = 0.0
	state["tool_cooldowns"] = cooldowns
	GameAuthority.player_states[ATTACKER_PEER_ID] = state


func _move_standard_targets_far(
	warrior: FutureWarriorAI,
	brick: BrickTool,
	target_proxy: CharacterBody3D
) -> void:
	warrior.global_position = FAR_POSITION
	brick.global_position = FAR_POSITION + Vector3.RIGHT * 2.0
	if target_proxy != null:
		target_proxy.global_position = FAR_POSITION + Vector3.RIGHT * 4.0
		var state: Dictionary = GameAuthority.player_states[TARGET_PEER_ID]
		state["position"] = target_proxy.global_position
		GameAuthority.player_states[TARGET_PEER_ID] = state


func _create_wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "SpearOcclusionWall"
	wall.collision_layer = 2
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.5, 0.15)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = Vector3(0.0, 1.2, -0.7)
	return wall


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[LongSpearCombatValidation] PASS ", description)
		return
	failures += 1
	push_error("[LongSpearCombatValidation] FAIL %s" % description)


func _capture_reliable_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "hit_confirmed":
		hit_confirmations.append(event.duplicate(true))
