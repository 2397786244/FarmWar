extends RefCounted
class_name CombatBalance

const BUG_STORM_DAMAGE_MULTIPLIER := 10.0
const MODEL_RECOIL_DURATION := 0.12

## Authoritative combat defaults. Scene export values may override these at
## runtime, but GameAuthority must never carry a second set of literals.
const PROFILES := {
	"fall_damage": {
		"start_height": 5.0,
		"damage_per_meter": 20.0,
		"max_damage": 200.0,
	},
	"team_rewards": {
		"enemy_player_kill": 200,
		"wild_animal_kill": 50,
		"crop_harvest": 5,
		"ore_mined": 50,
		"tree_chopped": 50,
		"giant_crop_destroyed": 500,
		"completed_dish_collected": 100,
	},
	"rubber_revolver": {
		"range": 60.0, "damage": 30.0, "knockback": 30.0,
		"visual_speed": 90.0, "visual_lifetime": 0.6666667,
		"camera_recoil_strength": 0.045, "camera_recoil_duration": 0.16,
		"model_recoil_y": 0.042, "model_recoil_z": 0.104,
	},
	"flame_gun": {
		"range": 100.0, "damage": 50.0, "knockback": 10.0,
		"visual_speed": 90.0, "visual_lifetime": 1.1111111,
		"camera_recoil_strength": 0.026, "camera_recoil_duration": 0.13,
		"model_recoil_y": 0.028, "model_recoil_z": 0.070,
	},
	"freeze_gun": {
		"range": 100.0, "damage": 50.0, "knockback": 10.0,
		"visual_speed": 90.0, "visual_lifetime": 1.1111111,
		"camera_recoil_strength": 0.026, "camera_recoil_duration": 0.13,
		"model_recoil_y": 0.028, "model_recoil_z": 0.070,
	},
	"nail_gun": {
		"range": 80.0, "damage": 20.0, "knockback": 15.0,
		"visual_speed": 120.0, "visual_lifetime": 0.6666667,
		"camera_recoil_strength": 0.030, "camera_recoil_duration": 0.12,
		"model_recoil_y": 0.024, "model_recoil_z": 0.060,
	},
	"suppressed_pistol": {
		"range": 100.0, "damage": 30.0, "knockback": 20.0,
		"visual_speed": 90.0, "visual_lifetime": 1.1111111,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.020, "camera_recoil_duration": 0.11,
		"model_recoil_y": 0.020, "model_recoil_z": 0.050,
	},
	"shotgun": {
		"range": 60.0, "damage": 60.0, "knockback": 30.0,
		"visual_speed": 100.0, "visual_lifetime": 0.6,
		"bullet_count": 6, "spread_degrees": 2.0,
		"camera_recoil_strength": 0.085, "camera_recoil_duration": 0.22,
		"model_recoil_y": 0.068, "model_recoil_z": 0.170,
	},
	"hunting_rifle": {
		"range": 150.0, "damage": 100.0, "knockback": 20.0,
		"visual_speed": 120.0, "visual_lifetime": 1.25,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.075, "camera_recoil_duration": 0.20,
		"model_recoil_y": 0.056, "model_recoil_z": 0.150,
	},
	"crossbow": {
		"range": 120.0, "damage": 80.0, "knockback": 20.0,
		"visual_speed": 90.0, "visual_lifetime": 1.3333333,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.060, "camera_recoil_duration": 0.18,
		"model_recoil_y": 0.048, "model_recoil_z": 0.130,
	},
	"long_spear": {
		"damage": 20.0, "reach": 2.4, "default_tip_distance": 1.35,
		"hitbox_width": 0.2, "hitbox_height": 0.2, "hitbox_depth": 0.3,
	},
	"medieval_shield": {
		"max_hp": 1000.0,
		"explosion_damage_multiplier": 0.20,
		"explosion_absorb_ratio": 0.80,
		"half_width": 0.66,
		"half_height": 0.80,
		"half_thickness": 0.10,
		"center_height": 1.20,
		"center_forward_offset": 0.55,
	},
	"m4": {
		"range": 120.0, "damage": 45.0, "knockback": 18.0,
		"visual_speed": 120.0, "visual_lifetime": 1.0,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.040, "camera_recoil_duration": 0.13,
		"model_recoil_y": 0.036, "model_recoil_z": 0.090,
	},
	"mpx": {
		"range": 100.0, "damage": 30.0, "knockback": 18.0,
		"visual_speed": 120.0, "visual_lifetime": 0.8333333,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.028, "camera_recoil_duration": 0.11,
		"model_recoil_y": 0.026, "model_recoil_z": 0.064,
	},
	"future_m4": {
		"range": 120.0, "damage": 48.0, "knockback": 20.0,
		"visual_speed": 140.0, "visual_lifetime": 0.8571429,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.045, "camera_recoil_duration": 0.13,
		"model_recoil_y": 0.040, "model_recoil_z": 0.100,
	},
	"future_mpx": {
		"range": 100.0, "damage": 35.0, "knockback": 18.0,
		"visual_speed": 120.0, "visual_lifetime": 0.8333333,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.032, "camera_recoil_duration": 0.11,
		"model_recoil_y": 0.030, "model_recoil_z": 0.074,
	},
	"ar15": {
		"range": 120.0, "damage": 55.0, "knockback": 20.0,
		"visual_speed": 120.0, "visual_lifetime": 1.0,
		"bullet_count": 1, "spread_degrees": 0.0,
		"camera_recoil_strength": 0.055, "camera_recoil_duration": 0.17,
		"model_recoil_y": 0.044, "model_recoil_z": 0.110,
	},
	"medicine_pistol": {
		"range": 60.0, "heal_amount": 50.0,
		"visual_speed": 48.0, "visual_lifetime": 2.0, "cooldown": 30.0,
		"camera_recoil_strength": 0.015, "camera_recoil_duration": 0.10,
		"model_recoil_y": 0.012, "model_recoil_z": 0.030,
	},
	"tranquilizer_pistol": {
		"range": 60.0, "damage": 5.0, "cooldown": 30.0,
		"visual_speed": 48.0, "visual_lifetime": 2.0,
		"effect_duration": 8.0, "flash_cycle": 2.0, "darkness_alpha": 0.82,
		"camera_recoil_strength": 0.018, "camera_recoil_duration": 0.11,
		"model_recoil_y": 0.016, "model_recoil_z": 0.040,
	},
	"wand": {"range": 80.0, "damage": 100.0},
	"wreck": {"projectile_speed": 30.0, "damage": 200.0, "radius": 12.0},
	# One point ensures the explosion immediately invokes FarmTile.impact("bug")
	# while the following cloud supplies the persistent growth-blocking effect.
	"bug_cannon": {"projectile_speed": 30.0, "damage": 1.0, "radius": 8.0},
	"medicine_cannon": {"projectile_speed": 48.0, "damage": 0.0, "radius": 20.0},
	"bug_storm": {
		"radius": 10.0, "lifetime": 15.0, "tick_interval": 1.0, "strength": 1.0,
		"fade_time": 2.5,
	},
	"medicine_storm": {
		"radius": 20.0, "lifetime": 20.0, "tick_interval": 1.0, "strength": 1.0,
	},
	"spicy_blaster": {
		"cooldown": 15.0, "projectile_speed": 20.0, "projectile_gravity": 4.5, "projectile_lifetime": 2.0,
		"projectile_range": 30.0, "projectile_strength": 0.0,
		"area_length": 16.0, "area_width": 8.0, "area_height": 0.8,
		"area_lifetime": 10.0, "area_fade_time": 2.0, "area_tick_interval": 0.25,
		"spicy_duration": 2.0, "spicy_dps": 5.0,
		"camera_recoil_strength": 0.018, "camera_recoil_duration": 0.12,
		"model_recoil_y": 0.016, "model_recoil_z": 0.040,
	},
	"fertilizer": {"range": 10.0, "growth_multiplier": 2.0},
	"eater": {"range": 10.0, "mature_plot_limit": 20, "projectile_limit": 2},
	"repair_welder": {"range": 4.0, "repair_amount": 10.0, "pulse_interval": 0.1},
	"vehicle_shield_shooter": {
		"projectile_speed": 60.0, "projectile_lifetime": 3.0,
		"shield_duration": 30.0, "shield_hp": 2000.0, "cooldown": 60.0,
	},
	"auto_shooter": {
		"target_range": 35.0, "projectile_speed": 30.0, "damage": 200.0,
		"radius": 12.0, "fire_interval": 10.0,
	},
	"wheat_sentry": {
		"target_range": 20.0, "projectile_speed": 60.0, "damage": 25.0,
		"impact_radius": 1.0, "direct_hit_radius": 0.56, "fire_interval": 1.5,
	},
	"anti_air": {
		"intercept_range": 15.0, "magazine_size": 8, "reload_time": 20.0,
		"visual_speed": 200.0,
	},
	"normal_drone": {
		"bomb_speed": 10.0, "bomb_damage": 200.0, "bomb_radius": 12.0,
		"bomb_cooldown": 2.0, "startup_bomb_lock": 3.0,
	},
	"tech_drone": {
		"move_speed": 10.0, "ascend_speed": 7.0, "signal_range": 100.0,
		"repair_range": 25.0, "repair_amount": 50.0, "emp_duration": 5.0,
		"lightning_disable_duration": 5.0, "flame_duration": 3.0,
		"flame_damage_multiplier": 1.0, "primary_cooldown": 6.0,
		"visual_speed": 60.0,
	},
	"remote_electronics": {
		"disable_duration": 5.0, "flame_duration": 3.0,
		"flame_damage_multiplier": 1.0,
	},
	"boom_buggy": {"damage": 200.0, "radius": 10.0},
	"vehicle_explosion": {
		"damage": 500.0, "radius_four_wheel": 8.5, "radius_two_wheel": 5.2,
		"knockback": 30.0,
	},
	"vehicle_impact": {
		"minimum_speed": 2.0, "damage_per_excess_speed": 25.0,
		"maximum_target_damage": 300.0, "self_damage_ratio": 0.25,
		"maximum_self_damage": 75.0, "contact_rearm_seconds": 0.30,
		"pair_cooldown_seconds": 0.65, "impact_speed_retention": 0.35,
		"push_velocity_per_force": 0.02, "empty_push_max_speed": 1.2,
		"occupied_push_multiplier": 0.20, "occupied_push_max_speed": 0.25,
		"push_decay": 2.5, "topple_window_seconds": 3.0,
		"topple_required_sources": 3, "topple_required_force": 60.0,
		"topple_angle_degrees": 82.0, "topple_response": 7.0,
		"upright_response": 10.0,
	},
	"small_mouse": {
		"range": 60.0, "damage": 5.0, "visual_speed": 60.0,
		"primary_cooldown": 1.0, "labeled_duration": 6.0,
	},
	"big_mouth": {
		"detection_length": 15.0, "detection_width": 2.0,
		"capture_seconds": 5.0, "rearm_cooldown": 15.0,
		"tongue_extend_seconds": 0.5, "tongue_retract_seconds": 0.5,
	},
	"area_protector": {
		"size_x": 12.0, "size_z": 8.0, "size_y": 6.0,
		"speed_multiplier": 0.1, "damage_multiplier": 0.5,
	},
	"rift_book": {
		"anchor_speed": 32.0, "anchor_lifetime": 0.8,
		"anchor_hp": 100.0, "teleport_cooldown": 0.35,
		"cooldown": 10.0,
	},
	"grenade": {
		"throw_speed": 30.0, "gravity": 18.0, "lifetime": 5.0,
		"damage": 300.0, "damage_radius": 10.0,
		"shake_radius": 20.0, "knockback": 24.0,
	},
	"black_bear": {
		"max_hp": 1000.0, "attack_damage": 50.0,
		"detection_range": 40.0, "attack_range": 2.2,
		"attack_hit_range": 2.25, "attack_exit_range": 2.65,
		"attack_approach_range": 3.5, "attack_approach_speed": 3.0,
		"wander_speed": 6.0, "chase_speed": 12.0, "flee_speed": 12.0,
		"wander_radius": 12.0, "chase_duration": 10.0,
		"rest_duration": 3.0, "attack_windup": 0.42,
		"attack_interval": 1.25, "flee_damage_threshold": 200.0,
		"flee_duration": 6.0, "death_visible_seconds": 4.0,
		"knockback_multiplier": 0.3, "max_knockback_speed": 4.0,
		"knockback_decay": 18.0, "immobilized_knockback_decay": 60.0,
		"flame_duration": 3.0, "flame_damage_per_second": 15.0,
		"freeze_duration": 2.0,
		"tranquilizer_duration": 8.0,
		"trap_duration": 2.0,
		"labeled_duration": 6.0,
	},
	"farm_livestock": {
		"chicken_hp": 200.0, "pig_hp": 400.0, "angus_cow_hp": 400.0,
		"chicken_meat_drop_count": 3, "pig_meat_drop_count": 5,
		"angus_cow_meat_drop_count": 6, "egg_interval_seconds": 30.0,
		"chicken_maturity_seconds": 180.0, "pig_maturity_seconds": 360.0,
		"angus_cow_maturity_seconds": 480.0, "angus_cow_milk_interval_seconds": 60.0,
		"golden_egg_chance": 0.10, "death_visible_seconds": 4.0,
		"trap_duration": 2.0,
	},
}

## All deployable/remote-device default health belongs here, including tools
## without a combat profile above.
const TOOL_MAX_HP := {
	"medieval_shield": 1000.0,
	"shield_door": 3000.0,
	"brick": 1000.0,
	"auto_shooter": 500.0,
	"wheat_sentry": 500.0,
	"anti_air": 500.0,
	"farm_runner": 260.0,
	"plant_protector": 500.0,
	"signal_jam": 500.0,
	"signal_augment": 500.0,
	"normal_drone": 200.0,
	"tech_drone": 180.0,
	"boom_buggy": 100.0,
	"small_mouse": 120.0,
	"automatic_cook": 500.0,
	"big_mouth": 200.0,
	"area_protector": 300.0,
	"fake_player": 300.0,
	"rift_anchor": 100.0,
	"tall_brick": 1800.0,
	"tall_log_wall": 1500.0,
	"tall_mesh_wall": 1200.0,
	"wire_mesh_gate": 1400.0,
	"chain_link_fence": 300.0,
	"default": 200.0,
}

## Electronic shutdown durations. RepairLaser EMP is intentionally uniform;
## Lightning scales with the device's battlefield impact and recovery cost.
const ELECTRONIC_STATUS := {
	"anti_air": {"repair_laser_duration": 5.0, "lightning_duration": 8.0},
	"auto_shooter": {"repair_laser_duration": 5.0, "lightning_duration": 7.0},
	"wheat_sentry": {"repair_laser_duration": 5.0, "lightning_duration": 6.0},
	"signal_jam": {"repair_laser_duration": 5.0, "lightning_duration": 8.0},
	"signal_augment": {"repair_laser_duration": 5.0, "lightning_duration": 8.0},
	"normal_drone": {"repair_laser_duration": 5.0, "lightning_duration": 5.0},
	"tech_drone": {"repair_laser_duration": 5.0, "lightning_duration": 6.0},
	"small_mouse": {"repair_laser_duration": 5.0, "lightning_duration": 4.0},
	"boom_buggy": {"repair_laser_duration": 5.0, "lightning_duration": 5.0},
	"farm_runner": {"repair_laser_duration": 5.0, "lightning_duration": 6.0},
	"plant_protector": {"repair_laser_duration": 5.0, "lightning_duration": 7.0},
}


static func get_float(profile: String, key: String, fallback: float = 0.0) -> float:
	var values: Dictionary = PROFILES.get(profile, {})
	return float(values.get(key, fallback))


static func get_model_recoil_offset(profile: String) -> Vector3:
	var values: Dictionary = PROFILES.get(profile, {})
	return Vector3(
		0.0,
		float(values.get("model_recoil_y", 0.025)),
		float(values.get("model_recoil_z", 0.07))
	)


static func get_bug_storm_impact_damage(strength: float) -> float:
	return maxf(0.0, strength) * BUG_STORM_DAMAGE_MULTIPLIER


static func get_int(profile: String, key: String, fallback: int = 0) -> int:
	var values: Dictionary = PROFILES.get(profile, {})
	return int(values.get(key, fallback))


static func calculate_fall_damage(fall_height: float) -> float:
	var excess_height := maxf(
		0.0,
		fall_height - get_float("fall_damage", "start_height", 5.0)
	)
	return minf(
		get_float("fall_damage", "max_damage", 200.0),
		excess_height * get_float("fall_damage", "damage_per_meter", 20.0)
	)


static func get_tool_max_hp(tool_id: String) -> float:
	return float(TOOL_MAX_HP.get(tool_id, TOOL_MAX_HP["default"]))


static func get_electronic_disable_duration(tool_id: String, effect: String) -> float:
	var values: Dictionary = ELECTRONIC_STATUS.get(tool_id, {})
	var key := "repair_laser_duration" if effect.to_lower() == "repair_laser" else "lightning_duration"
	return float(values.get(key, 5.0))
