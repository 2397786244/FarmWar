extends Node3D

const WARRIOR_SCENE := preload("res://character/FutureWarriorAI.tscn")
const ENGINEER_SCENE := preload("res://character/FutureEngineerAI.tscn")

var failures := 0


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode()
	var victim := WARRIOR_SCENE.instantiate() as FutureWarriorAI
	var attacker := WARRIOR_SCENE.instantiate() as FutureWarriorAI
	victim.team_id = "blue"
	attacker.team_id = "red"
	victim.server_authoritative = false
	attacker.server_authoritative = false
	victim.print_decisions = true
	add_child(victim)
	add_child(attacker)
	victim.global_position = Vector3.ZERO
	attacker.global_position = Vector3(0.0, 0.0, -10.0)
	await get_tree().physics_frame

	_check(victim.ar15_tool_id == "future_m4", "default weapon is FutureM4")
	_check(victim._weapon_magazine_capacity(FutureWarriorAI.WeaponSlot.AR15) == 60,
		"FutureM4 magazine matches player config (60)")
	_check(victim._weapon_magazine_capacity(FutureWarriorAI.WeaponSlot.SUPPRESSED_PISTOL) == 30,
		"SuppressedPistol magazine matches player config (30)")
	_check(victim.grenades_remaining == 2, "FutureWarrior starts with two grenades")
	var tagged_bullet := NailBullet.new()
	add_child(tagged_bullet)
	tagged_bullet.run(Vector3.ZERO, Vector3.FORWARD, "red", attacker)
	_check(tagged_bullet.get_bullet_shooter() == attacker,
		"FutureM4 projectile preserves its shooter reference")
	remove_child(tagged_bullet)
	tagged_bullet.free()
	var hp_before_ai_hitscan := victim.current_hp
	var ai_fire_origin := attacker.held_weapon.call("get_fire_origin") as Vector3
	var ai_fire_direction := (
		victim.global_position + Vector3.UP * 0.85 - ai_fire_origin
	).normalized()
	var ai_hitscan_result: Dictionary = GameAuthority.server_ai_hitscan(
		attacker,
		attacker.team_id,
		"future_m4",
		ai_fire_origin,
		ai_fire_direction
	)
	_check(bool(ai_hitscan_result.get("ok", false)),
		"FutureM4 AI shot uses the authority hitscan endpoint")
	_check(victim.current_hp < hp_before_ai_hitscan,
		"FutureM4 AI hitscan damages an enemy FutureWarrior")
	victim.process_mode = Node.PROCESS_MODE_DISABLED
	attacker.process_mode = Node.PROCESS_MODE_DISABLED

	victim.state = FutureWarriorAI.AIState.SEARCH
	victim.target_player = null
	victim.impact("bullet", 1.0, "red", victim.global_position - attacker.global_position, attacker)
	_check(victim.target_player == attacker, "damage immediately locks the actual attacker")
	_check(victim.state != FutureWarriorAI.AIState.FLEE, "retaliation does not enter delayed flee state")
	_check(victim.engagement_grenade_pending, "new firefight schedules one grenade")
	var grenade_projectiles_before := GameAuthority.projectile_states.size()
	victim._try_throw_grenade(10.0)
	_check(victim.grenades_remaining == 1, "firefight throws exactly one grenade")
	_check(not victim.engagement_grenade_pending, "same engagement does not schedule a second grenade")
	_check(GameAuthority.projectile_states.size() == grenade_projectiles_before + 1,
		"AI grenade enters the authoritative player grenade pipeline")

	_set_magazine(victim, FutureWarriorAI.WeaponSlot.AR15, 0)
	_set_magazine(victim, FutureWarriorAI.WeaponSlot.SUPPRESSED_PISTOL, 2)
	victim.fire_timer = 0.0
	victim._try_fire_at_target(10.0)
	_check(victim.current_weapon_slot == FutureWarriorAI.WeaponSlot.SUPPRESSED_PISTOL,
		"empty FutureM4 switches to loaded pistol during firefight")
	_check(victim._weapon_ammo_in_mag(FutureWarriorAI.WeaponSlot.SUPPRESSED_PISTOL) == 1,
		"pistol shot consumes one round")

	_set_magazine(victim, FutureWarriorAI.WeaponSlot.AR15, 0)
	_set_magazine(victim, FutureWarriorAI.WeaponSlot.SUPPRESSED_PISTOL, 0)
	victim.fire_timer = 0.0
	victim._try_fire_at_target(10.0)
	_check(victim.current_weapon_slot == FutureWarriorAI.WeaponSlot.AR15,
		"both empty switches back to FutureM4")
	_check(victim.reloading_weapon_slot == FutureWarriorAI.WeaponSlot.AR15,
		"both empty starts FutureM4 reload")
	victim._update_timers(victim.weapon_reload_timer + 0.1)
	_check(victim._weapon_ammo_in_mag(FutureWarriorAI.WeaponSlot.AR15) == 60,
		"FutureM4 reload refills its player-configured magazine")

	var engineer := ENGINEER_SCENE.instantiate() as FutureEngineerAI
	engineer.server_authoritative = false
	add_child(engineer)
	await get_tree().process_frame
	engineer.process_mode = Node.PROCESS_MODE_DISABLED
	_check(engineer._weapon_magazine_capacity(FutureWarriorAI.WeaponSlot.AR15) == 20,
		"FutureMPX magazine matches player config (20)")
	_check(not engineer.weapon_data.has(FutureWarriorAI.WeaponSlot.SUPPRESSED_PISTOL),
		"FutureEngineer still has no pistol")
	_check(engineer.grenades_remaining == 0, "FutureEngineer still has no grenades")
	engineer.target_player = attacker
	_set_magazine(engineer, FutureWarriorAI.WeaponSlot.AR15, 0)
	engineer._try_fire_at_target(10.0)
	_check(engineer.reloading_weapon_slot == FutureWarriorAI.WeaponSlot.AR15,
		"empty FutureMPX reloads with the same player-configured timing")

	if failures == 0:
		print("[FutureWarriorCombatValidation] PASS all checks")
	else:
		push_error("[FutureWarriorCombatValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _set_magazine(warrior: FutureWarriorAI, slot: int, amount: int) -> void:
	var ammo_state: Dictionary = warrior.weapon_ammo.get(slot, {})
	ammo_state["ammo_in_mag"] = maxi(0, amount)
	warrior.weapon_ammo[slot] = ammo_state


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[FutureWarriorCombatValidation] PASS ", description)
		return
	failures += 1
	push_error("[FutureWarriorCombatValidation] FAIL %s" % description)
