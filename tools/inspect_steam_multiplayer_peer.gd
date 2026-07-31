extends SceneTree


func _initialize() -> void:
	var peer_class := "SteamMultiplayerPeer"
	print("SteamMultiplayerPeer registered: %s" % ClassDB.class_exists(peer_class))
	if ClassDB.class_exists(peer_class):
		for method_info: Dictionary in ClassDB.class_get_method_list(peer_class):
			var method_name := str(method_info.get("name", ""))
			if method_name in ["create_host", "create_client", "host_with_lobby", "connect_to_lobby", "add_peer"]:
				print("SteamMultiplayerPeer signature: %s" % method_info)
	quit()
