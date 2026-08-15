extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const REQUIRED_NODES := [
	"Mesh", "MachineGunYawPivot", "MachineGunPitchPivot", "BaseHit3D",
	"GunHit3D", "StandPos", "Muzzle", "MuzzleFlash", "RightHandGrip",
]

var failures := 0
var hit_confirmations := 0


class DamageDummy extends StaticBody3D:
	var hp := 100.0

	func configure() -> void:
		collision_layer = GameAuthority.COLLISION_LAYER_TOOL
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, 1.0, 1.0)
		collision.shape = shape
		add_child(collision)

	func impact(_effect: String, damage: float, _attacker_team: String = "") -> bool:
		hp = maxf(0.0, hp - damage)
		return damage > 0.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	vehicle.platform_machine_gun_installed = true
	vehicle.owner_team = "red"
	vehicle.network_id = "machine_gun_test_vehicle"
	add_child(vehicle)
	await get_tree().process_frame
	var machine_gun := vehicle.get_platform_machine_gun()
	_check(machine_gun != null, "FarmBaseVehicle installs the optional machine gun")
	if machine_gun == null:
		_finish()
		return
	for node_name: String in REQUIRED_NODES:
		_check(machine_gun.find_child(node_name, true, false) != null, "recursive find_child locates %s" % node_name)
	_check(is_equal_approx(machine_gun.current_hp, 1000.0), "machine gun starts with 1000 HP")
	_check(is_equal_approx(VehicleBaseMachineGun.DAMAGE, 35.0), "damage is 35")
	_check(is_equal_approx(VehicleBaseMachineGun.RANGE_METERS, 120.0), "range is 120 metres")
	_check(is_equal_approx(VehicleBaseMachineGun.FIRE_COOLDOWN_SECONDS, 0.2), "cooldown is 0.2 seconds")
	_check(machine_gun.collision_layer == 0 and machine_gun.collision_mask == 0, "mounted StaticBody cannot collide with its parent vehicle")
	var expected_visual_speed := CombatBalance.get_float("nail_gun", "visual_speed", 90.0) * VehicleBaseMachineGun.VISUAL_SPEED_MULTIPLIER
	_check(is_equal_approx(machine_gun.get_visual_speed(), expected_visual_speed) \
			and is_equal_approx(machine_gun.get_visual_speed(), 240.0),
		"mounted NailBullet visual speed is doubled to 240 m/s")
	_check(is_equal_approx(VehicleBaseMachineGun.RANGE_METERS, 120.0) \
			and is_equal_approx(VehicleBaseMachineGun.RANGE_METERS / machine_gun.get_visual_speed(), 0.5),
		"mounted visual and hitscan maximum distance share 120 metres")
	var base_combat_area := machine_gun.find_child("BaseHit3D", true, false) as Area3D
	var gun_combat_area := machine_gun.find_child("GunHit3D", true, false) as Area3D
	_check(base_combat_area.collision_layer == GameAuthority.COLLISION_LAYER_TOOL \
			and gun_combat_area.collision_layer == GameAuthority.COLLISION_LAYER_TOOL,
		"both Hit3D areas remain on the combat TOOL layer")
	_check(GamePlayer.MOUNTED_MACHINE_GUN_COLLISION_MASK == GameAuthority.COLLISION_LAYER_GROUND,
		"mounted gunner keeps ground collision instead of using a zero mask")
	_check((GamePlayer.MOUNTED_MACHINE_GUN_COLLISION_MASK & GameAuthority.COLLISION_LAYER_VEHICLES) == 0,
		"mounted gunner collision mask excludes its carrier vehicle")

	var base_hit := machine_gun.find_child("BaseHit3D", true, false) as Area3D
	var base_before := base_hit.global_transform
	var gun_hit := machine_gun.find_child("GunHit3D", true, false) as Area3D
	var muzzle := machine_gun.find_child("Muzzle", true, false) as Marker3D
	var stand_pos := machine_gun.find_child("StandPos", true, false) as Marker3D
	var gun_hit_before := gun_hit.global_transform
	var muzzle_before := muzzle.global_transform
	var stand_before := stand_pos.global_transform
	machine_gun.set_aim(200.0, 90.0)
	_check(is_equal_approx(machine_gun.yaw_degrees, 120.0), "yaw clamps at +120 degrees")
	_check(is_equal_approx(machine_gun.elevation_degrees, 45.0), "elevation clamps at 45 degrees")
	_check(base_hit.global_transform.is_equal_approx(base_before), "BaseHit3D remains fixed while aiming")
	_check(not gun_hit.global_transform.is_equal_approx(gun_hit_before), "GunHit3D follows yaw and pitch")
	_check(not muzzle.global_transform.is_equal_approx(muzzle_before), "Muzzle follows yaw and pitch")
	_check(not stand_pos.global_transform.is_equal_approx(stand_before), "StandPos follows yaw")
	machine_gun.set_aim(-200.0, -90.0)
	_check(is_equal_approx(machine_gun.yaw_degrees, -120.0), "yaw clamps at -120 degrees")
	_check(is_equal_approx(machine_gun.elevation_degrees, -25.0), "elevation clamps at -25 degrees")
	_check(machine_gun.get_fire_direction().y < 0.0, "negative elevation aims the +Z muzzle downward")
	machine_gun.set_aim(25.0, 0.0)
	var stand_without_pitch := stand_pos.global_transform
	machine_gun.set_aim(25.0, 30.0)
	_check(stand_pos.global_transform.is_equal_approx(stand_without_pitch), "StandPos ignores pitch")
	_check(machine_gun.get_fire_direction().y > 0.0, "positive elevation aims the +Z muzzle upward")
	machine_gun.set_aim(0.0, 0.0)

	var passive_hp := machine_gun.current_hp
	for _index in range(3):
		await get_tree().physics_frame
	_check(is_equal_approx(machine_gun.current_hp, passive_hp), "passive Hit3D overlap does not deal damage")

	GameAuthority.start_local_mode({
		"display_name": "MachineGunner", "team": "red", "position": machine_gun.global_position,
		"primary_weapon_ids": [], "special_tool_ids": [],
	})
	GameAuthority.set_physics_process(false)
	GameAuthority.call("_register_world_vehicles")
	if not GameAuthority.reliable_world_event_ready.is_connected(_capture_event):
		GameAuthority.reliable_world_event_ready.connect(_capture_event)
	GameAuthority.register_or_update_player(2, {
		"display_name": "EnemyGunner", "team": "blue", "position": machine_gun.global_position,
		"primary_weapon_ids": [], "special_tool_ids": [],
	})
	var enemy_enter := GameAuthority.call(
		"_server_mounted_machine_gun_session", 2, vehicle.get_vehicle_id(), true
	) as Dictionary
	_check(not bool(enemy_enter.get("ok", false)) and str(enemy_enter.get("reason", "")) == "wrong_team", "enemy team cannot operate the mounted gun")
	var enter_result := GameAuthority.call(
		"_server_mounted_machine_gun_session", 1, vehicle.get_vehicle_id(), true
	) as Dictionary
	_check(bool(enter_result.get("ok", false)), "authority accepts an in-range same-team operator")
	_check(machine_gun.operator_peer_id == 1, "machine gun records its operator")
	GameAuthority.register_or_update_player(3, {
		"display_name": "SecondGunner", "team": "red", "position": machine_gun.global_position,
		"primary_weapon_ids": [], "special_tool_ids": [],
	})
	var occupied_enter := GameAuthority.call(
		"_server_mounted_machine_gun_session", 3, vehicle.get_vehicle_id(), true
	) as Dictionary
	_check(not bool(occupied_enter.get("ok", false)) and str(occupied_enter.get("reason", "")) == "machine_gun_in_use", "only one operator can control the gun")
	var recoil_player := GamePlayer.new()
	recoil_player.mounted_machine_gun_is_active = true
	recoil_player.trigger_mounted_machine_gun_recoil()
	_check(recoil_player.camera_shake_time > 0.0 \
			and is_equal_approx(recoil_player.camera_shake_strength, 0.03) \
			and is_equal_approx(recoil_player.camera_shake_duration, 0.13),
		"mounted machine gun recoil triggers a light local camera shake")
	recoil_player.free()

	var target := DamageDummy.new()
	target.configure()
	add_child(target)
	target.global_position = machine_gun.get_muzzle_origin() + (
		machine_gun.get_fire_direction() + Vector3.RIGHT * 0.35
	).normalized() * 8.0
	await get_tree().physics_frame
	var first_shot := GameAuthority.call(
		"_server_mounted_machine_gun_fire", 1, vehicle.get_vehicle_id(), target.global_position
	) as Dictionary
	var second_shot := GameAuthority.call(
		"_server_mounted_machine_gun_fire", 1, vehicle.get_vehicle_id()
	) as Dictionary
	_check(bool(first_shot.get("ok", false)), "first click fires")
	_check(not bool(second_shot.get("ok", false)) and str(second_shot.get("reason", "")) == "cooldown", "second click inside 0.2 seconds is rejected")
	_check(is_equal_approx(target.hp, 65.0), "one accepted shot deals exactly 35 damage")
	_check(hit_confirmations == 1, "mounted gun uses the existing hit_confirmed event")
	var local_nail_visuals := get_tree().get_nodes_in_group("local_transient_projectile_visuals")
	_check(not local_nail_visuals.is_empty() and local_nail_visuals[0] is NailBullet,
		"single-player mounted gun spawns a NailBullet visual")

	var vehicle_hp_before := vehicle.current_hp
	machine_gun.impact("nail", 1000.0, "blue")
	_check(machine_gun.destroyed_state and is_zero_approx(machine_gun.current_hp), "1000 damage destroys the machine gun")
	_check(is_equal_approx(vehicle.current_hp, vehicle_hp_before), "destroying the gun does not damage FarmBaseVehicle")
	_check(str((GameAuthority.player_states[1] as Dictionary).get("mounted_machine_gun_vehicle_id", "")).is_empty(), "destruction releases the operator")
	_check((GameAuthority.player_states[1] as Dictionary).get("position", Vector3.ZERO) is Vector3, "released operator keeps a platform world position")
	var released_player := GamePlayer.new()
	released_player.mounted_machine_gun_is_active = true
	released_player.collision_layer = 0
	released_player.collision_mask = GamePlayer.MOUNTED_MACHINE_GUN_COLLISION_MASK
	released_player.call("_restore_mounted_machine_gun_player_state", Vector3(4.0, 2.0, 1.0))
	_check(not released_player.mounted_machine_gun_is_active, "destroyed gun clears the player's mounted state")
	_check(released_player.collision_layer == GamePlayer.PLAYER_COLLISION_LAYER \
			and released_player.collision_mask == GamePlayer.PLAYER_COLLISION_MASK,
		"destroyed gun restores the player's normal collision layer and mask")
	released_player.free()

	GameAuthority.stop_authority()
	GameAuthority.set_physics_process(true)
	_finish()


func _capture_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "hit_confirmed" and int(event.get("attacker_peer_id", 0)) == 1:
		hit_confirmations += 1


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[VehicleBaseMachineGunValidation] PASS: %s" % message)
	else:
		failures += 1
		push_error("[VehicleBaseMachineGunValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures == 0:
		print("[VehicleBaseMachineGunValidation] PASS all checks")
	else:
		push_error("[VehicleBaseMachineGunValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
