extends Node3D

const PLAYER_SCENE := preload("res://character/player.tscn")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	_check(player != null, "player scene creates a GamePlayer")
	if player == null:
		_finish()
		return
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	# The local authority path owns the death camera and overlay in a normal
	# single-player/listen-server presentation.
	GameAuthority.mode = GameAuthority.MODE_LOCAL
	player.authority_peer_id = GameAuthority.local_player_id
	_check(
		player.appearance_player != null
			and player.appearance_player.has_animation(&"DeathFallForward"),
		"default hero provides DeathFallForward"
	)

	player.appearance_player.play(&"ShootOneHand")
	player.apply_respawn_state(10.0)
	_check(player.is_respawning, "respawn state enters the death presentation")
	_check(
		player.appearance_player.current_animation == &"DeathFallForward",
		"death animation replaces the firing animation immediately"
	)
	_check(player.get_node("AppearanceNode").visible, "corpse stays visible")
	_check(
		is_instance_valid(player.respawn_label)
			and player.respawn_label.visible
			and player.respawn_label.text == "你死了",
		"death UI shows only the large death message"
	)
	_check(
		is_instance_valid(player.respawn_overlay)
			and is_zero_approx(player.respawn_overlay.color.a),
		"death overlay remains transparent instead of black"
	)

	# Reproduce the tail of _use_current_tool(): its animation request must be
	# rejected after authoritative damage has already killed the shooter.
	player._play_character_animation(&"ShootOneHand")
	player._set_tool_action()
	_check(
		player.appearance_player.current_animation == &"DeathFallForward",
		"late firing animation cannot overwrite death animation"
	)
	player._play_death_animation()
	_check(
		player.death_animation_started
			and player.appearance_player.current_animation == &"DeathFallForward",
		"death animation starts exactly once during the death presentation"
	)

	player.respawn_left = 4.0
	player._update_death_appearance_visibility()
	player._update_respawn_overlay()
	_check(player.get_node("AppearanceNode").visible, "corpse remains visible near respawn")
	_check(player.respawn_label.visible, "death message remains visible near respawn")
	_check(is_zero_approx(player.respawn_overlay.color.a), "overlay stays transparent near respawn")

	player.apply_respawn_state(0.0, Vector3.ZERO)
	_check(not player.is_respawning, "respawn state exits normally")
	_check(not player.respawn_label.visible, "death message hides after respawn")
	player.cooldown_ring.call("set_progress", 0.4, 1.0)
	player.mounted_machine_gun_is_active = true
	player._set_mounted_machine_gun_runtime(true)
	_check(not player.cooldown_ring.visible, "mounted machine gun hides the hand-tool cooldown ring")
	player.mounted_machine_gun_is_active = false
	player._set_mounted_machine_gun_runtime(false)

	player.queue_free()
	GameAuthority.stop_authority()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[PlayerDeathPresentationValidation] PASS all checks")
	else:
		push_error("[PlayerDeathPresentationValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PlayerDeathPresentationValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[PlayerDeathPresentationValidation] FAIL: %s" % description)
