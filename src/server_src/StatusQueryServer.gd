extends Node
class_name StatusQueryServer

@export var query_port := 2003
@export var auto_start := false

var tcp_server := TCPServer.new()
@export var server_manager: DedicatedServerManager
var clients: Array[StreamPeerTCP] = []
var is_running := false


func _ready() -> void:
	if auto_start:
		start_query_server()


func start_query_server() -> bool:
	if is_running:
		return true

	if server_manager == null:
		server_manager = get_parent() as DedicatedServerManager
	if server_manager == null:
		server_manager = get_tree().get_first_node_in_group("dedicated_server_manager") as DedicatedServerManager
	if server_manager == null:
		push_error("StatusQueryServer 找不到 DedicatedServerManager，请把它作为 DedicatedServerManager 子节点，或手动设置 server_manager。")
		return false

	var err := tcp_server.listen(query_port, "0.0.0.0")

	if err != OK:
		push_error("状态查询服务器启动失败，端口：%d，错误码：%d" % [query_port, err])
		return false

	is_running = true
	print("状态查询服务器启动成功，监听 TCP 端口：", query_port)
	set_process(true)
	return true


func _process(_delta: float) -> void:
	if not is_running:
		return
	_accept_new_clients()
	_process_clients()


func _accept_new_clients() -> void:
	while tcp_server.is_connection_available():
		var client := tcp_server.take_connection()

		if client == null:
			continue

		clients.append(client)


func _process_clients() -> void:
	for i in range(clients.size() - 1, -1, -1):
		var client := clients[i]

		client.poll()

		var status := client.get_status()

		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			clients.remove_at(i)
			continue

		if status != StreamPeerTCP.STATUS_CONNECTED:
			continue

		# 等客户端发来 HTTP 请求后再回复。
		if client.get_available_bytes() <= 0:
			continue

		var _request_text := client.get_utf8_string(client.get_available_bytes())

		_send_status_response(client)

		client.disconnect_from_host()
		clients.remove_at(i)


func _send_status_response(client: StreamPeerTCP) -> void:
	var info := server_manager.get_server_public_info()

	# 查询接口建议永远返回地图名。
	# 之前你的 UI 逻辑是 IN_GAME 才显示地图名；
	# 但是服务器列表通常希望等待玩家时也显示地图。
	info["map_id"] = server_manager.current_map_id
	info["map_name"] = server_manager.current_map_name
	info["game_port"] = server_manager.port
	info["query_port"] = query_port
	info["status_protocol"] = 1
	info["unix_time"] = int(Time.get_unix_time_from_system())
	if info.has("metrics") and info["metrics"] is Dictionary:
		var metrics: Dictionary = info["metrics"]
		for key in metrics.keys():
			info[key] = metrics[key]

	var body := JSON.stringify(info)
	var body_bytes := body.to_utf8_buffer()

	var response := ""
	response += "HTTP/1.1 200 OK\r\n"
	response += "Content-Type: application/json; charset=utf-8\r\n"
	response += "Content-Length: %d\r\n" % body_bytes.size()
	response += "Connection: close\r\n"
	response += "\r\n"
	response += body

	client.put_data(response.to_utf8_buffer())


func stop_query_server() -> void:
	for client in clients:
		if client != null:
			client.disconnect_from_host()

	clients.clear()
	tcp_server.stop()
	is_running = false
	set_process(false)

	print("状态查询服务器已关闭。")
