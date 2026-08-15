extends Node
class_name SquadCommunicationChannel

const Message := preload("res://src/squad_message.gd")

## 服务器权威频道每次实际广播时发出，测试 UI 和调试工具可订阅；
## 这不是持久消息队列，监听者仍需在广播时实时处理。
signal message_broadcast(message: Dictionary)

@export var demolition_point_merge_radius := 2.0
## 炸药安装后的 Squad 撤退通知统一覆盖 10m 安全距离。
## 调用方传入更小的值时，频道仍会使用这个最低值。
@export var demolition_warning_radius := 10.0
@export_range(1, 8, 1) var max_support_responders := 2
@export var support_request_lifetime := 15.0
@export var debug_enabled := true

var squad: Node
var _members: Dictionary = {}
var _demolition_tasks: Dictionary = {}
var _support_tasks: Dictionary = {}
var _message_serial := 0
var _request_serial := 0


func _process(_delta: float) -> void:
	_cleanup_members()
	_cleanup_tasks()


func configure(value_squad: Node) -> void:
	squad = value_squad


func register_member(member_id: String, communicator: Node) -> bool:
	if member_id.is_empty() or not is_instance_valid(communicator):
		return false
	_members[member_id] = communicator
	return true


func unregister_member(member_id: String) -> void:
	_members.erase(member_id)
	for request_id in _demolition_tasks.keys():
		var task: Dictionary = _demolition_tasks[request_id]
		if task.get("owner_id", "") == member_id:
			release_demolition(request_id, member_id, "member_removed")
	for request_id in _support_tasks.keys():
		var task: Dictionary = _support_tasks[request_id]
		var responders: Array = task.get("responders", [])
		responders.erase(member_id)


func send_message(sender_id: String, type: int, payload: Dictionary = {}, reply_to: String = "") -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	if not _members.has(sender_id) and sender_id != "squad":
		return {"accepted": false, "reason": "unknown_member"}
	match type:
		Message.Type.SET_TARGET:
			return _send_target(sender_id, payload.get("target") as Node3D)
		Message.Type.DEMOLITION_REQUEST:
			return request_demolition(
				sender_id,
				payload.get("target") as Node3D,
				payload.get("position", Vector3.ZERO),
				payload.get("normal", Vector3.UP)
			)
		Message.Type.DEMOLITION_CLAIM:
			return claim_demolition(sender_id, reply_to)
		Message.Type.DEMOLITION_WARNING:
			return mark_demolition_planted(reply_to, sender_id, payload.get("position", Vector3.ZERO), payload.get("radius", demolition_warning_radius))
		Message.Type.NAVIGATION_REFRESH:
			return {"accepted": complete_demolition(reply_to, sender_id, payload.get("position", Vector3.INF))}
		Message.Type.SUPPORT_REQUEST:
			return request_support(sender_id, payload.get("position", Vector3.ZERO))
		Message.Type.SUPPORT_ACK:
			return claim_support(sender_id, reply_to)
	return {"accepted": false, "reason": "unsupported_type"}


func broadcast_target(target: Node3D) -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	return _send_target("squad", target)


func request_demolition(sender_id: String, target: Node3D, position: Vector3, normal := Vector3.UP) -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	var duplicate_id := _find_duplicate_demolition(target, position)
	if not duplicate_id.is_empty():
		return {"accepted": false, "reason": "duplicate", "request_id": duplicate_id}
	var request_id := _next_request_id("demolition")
	_demolition_tasks[request_id] = {
		"request_id": request_id,
		"target": target,
		"target_key": _target_key(target),
		"position": position,
		"normal": normal,
		"owner_id": "",
		"state": "open",
		"created_msec": Time.get_ticks_msec(),
		"plant_attempt": 0,
	}
	var message := _make_message(Message.Type.DEMOLITION_REQUEST, sender_id, {"position": position}, request_id)
	_broadcast(message)
	_debug_message(message)
	return {"accepted": true, "request_id": request_id, "task": _demolition_tasks.get(request_id, {})}


## Engineer 自主发现时也必须进入频道的内部占用表，以免多个工程师重复放置。
## 若已有公开请求，则原子认领该请求；没有时创建一个不广播“需要爆破”的内部任务。
func reserve_self_detected_demolition(sender_id: String, target: Node3D, position: Vector3, normal := Vector3.UP) -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	var duplicate_id := _find_duplicate_demolition(target, position)
	if not duplicate_id.is_empty():
		var existing: Dictionary = _demolition_tasks[duplicate_id]
		if existing.get("owner_id", "") == sender_id:
			return {"accepted": true, "request_id": duplicate_id, "task": existing}
		if existing.get("state", "") == "open":
			return claim_demolition(sender_id, duplicate_id)
		return {"accepted": false, "reason": "already_claimed", "request_id": duplicate_id}
	var request_id := _next_request_id("demolition")
	_demolition_tasks[request_id] = {
		"request_id": request_id,
		"target": target,
		"target_key": _target_key(target),
		"position": position,
		"normal": normal,
		"owner_id": sender_id,
		"state": "claimed",
		"created_msec": Time.get_ticks_msec(),
		"plant_attempt": 0,
		"self_detected": true,
	}
	return {"accepted": true, "request_id": request_id, "task": _demolition_tasks[request_id]}


func claim_demolition(sender_id: String, request_id: String) -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	if not _demolition_tasks.has(request_id):
		return {"accepted": false, "reason": "request_missing"}
	var task: Dictionary = _demolition_tasks[request_id]
	if task.get("state", "") != "open" or not task.get("owner_id", "").is_empty():
		return {"accepted": false, "reason": "claim_taken", "request_id": request_id}
	var member := _get_member_ai(sender_id)
	if not is_instance_valid(member) or not member.has_method("is_available_for_demolition") or not member.is_available_for_demolition():
		return {"accepted": false, "reason": "member_unavailable", "request_id": request_id}
	task["owner_id"] = sender_id
	task["state"] = "claimed"
	_demolition_tasks[request_id] = task
	var message := _make_message(Message.Type.DEMOLITION_CLAIM, sender_id, {"member_id": sender_id}, request_id, request_id)
	_broadcast(message)
	_debug_message(message)
	return {"accepted": true, "request_id": request_id, "task": task}


func mark_demolition_planted(request_id: String, sender_id: String, position: Vector3, radius: float) -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	if not _demolition_tasks.has(request_id):
		return {"accepted": false, "reason": "request_missing"}
	var task: Dictionary = _demolition_tasks[request_id]
	if task.get("owner_id", "") != sender_id:
		return {"accepted": false, "reason": "not_owner"}
	task["state"] = "planted"
	task["position"] = position
	task["plant_attempt"] = int(task.get("plant_attempt", 0)) + 1
	_demolition_tasks[request_id] = task
	var warning_radius := maxf(radius, demolition_warning_radius)
	var message := _make_message(
		Message.Type.DEMOLITION_WARNING,
		sender_id,
		{"position": position, "radius": warning_radius},
		request_id,
		request_id
	)
	_broadcast(message)
	_debug_message(message)
	return {"accepted": true, "request_id": request_id}


func complete_demolition(request_id: String, sender_id: String, demolished_position: Vector3) -> bool:
	if not _is_authority():
		return false
	if not _demolition_tasks.has(request_id):
		return false
	var task: Dictionary = _demolition_tasks[request_id]
	if task.get("owner_id", "") != sender_id:
		return false
	if not demolished_position.is_finite():
		return false
	## 爆破任务完成时广播一次导航刷新。请求表在广播后才删除，保证同一
	## request_id 的重复确认不会产生第二条“重新更新导航”消息。
	var message := _make_message(
		Message.Type.NAVIGATION_REFRESH,
		sender_id,
		{"position": demolished_position},
		request_id,
		request_id
	)
	_broadcast(message)
	_debug_message(message)
	_demolition_tasks.erase(request_id)
	return true


func release_demolition(request_id: String, sender_id: String, reason := "released") -> bool:
	if not _is_authority():
		return false
	if not _demolition_tasks.has(request_id):
		return false
	var task: Dictionary = _demolition_tasks[request_id]
	if task.get("owner_id", "") != sender_id:
		return false
	if _is_task_target_active(task):
		task["owner_id"] = ""
		task["state"] = "open"
		task["release_reason"] = reason
		_demolition_tasks[request_id] = task
		var message := _make_message(
			Message.Type.DEMOLITION_REQUEST,
			"squad",
			{"position": task.get("position", Vector3.ZERO)},
			request_id
		)
		_broadcast(message)
		_debug_message(message)
	else:
		_demolition_tasks.erase(request_id)
	return true


func request_support(sender_id: String, position: Vector3) -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	var request_id := _next_request_id("support")
	_support_tasks[request_id] = {
		"request_id": request_id,
		"sender_id": sender_id,
		"position": position,
		"responders": [],
		"created_msec": Time.get_ticks_msec(),
	}
	var message := _make_message(Message.Type.SUPPORT_REQUEST, sender_id, {"position": position}, request_id)
	_broadcast(message)
	_debug_message(message)
	return {"accepted": true, "request_id": request_id}


func claim_support(sender_id: String, request_id: String) -> Dictionary:
	if not _is_authority():
		return {"accepted": false, "reason": "not_authority"}
	if not _support_tasks.has(request_id):
		return {"accepted": false, "reason": "request_missing"}
	var task: Dictionary = _support_tasks[request_id]
	if task.get("sender_id", "") == sender_id:
		return {"accepted": false, "reason": "self_request"}
	var responders: Array = task.get("responders", [])
	if sender_id in responders:
		return {"accepted": false, "reason": "already_responding"}
	if responders.size() >= max_support_responders:
		return {"accepted": false, "reason": "response_limit"}
	responders.append(sender_id)
	task["responders"] = responders
	_support_tasks[request_id] = task
	var message := _make_message(Message.Type.SUPPORT_ACK, sender_id, {"member_id": sender_id}, request_id, request_id)
	_broadcast(message)
	_debug_message(message)
	return {"accepted": true, "request_id": request_id, "position": task.get("position", Vector3.ZERO)}


func get_demolition_task(request_id: String) -> Dictionary:
	if not _demolition_tasks.has(request_id):
		return {}
	return (_demolition_tasks[request_id] as Dictionary).duplicate()


func get_member_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for communicator in _members.values():
		if is_instance_valid(communicator) and is_instance_valid(communicator.owner_ai):
			result.append(communicator.owner_ai)
	return result


func _send_target(sender_id: String, target: Node3D) -> Dictionary:
	if not is_instance_valid(target):
		return {"accepted": false, "reason": "invalid_target"}
	var message := _make_message(Message.Type.SET_TARGET, sender_id, {"target": target})
	_broadcast(message)
	_debug_message(message)
	return {"accepted": true}


func _make_message(type: int, sender_id: String, payload: Dictionary, request_id := "", reply_to := "") -> Dictionary:
	_message_serial += 1
	return Message.make("message_%d" % _message_serial, type, sender_id, payload, request_id, reply_to)


func _next_request_id(prefix: String) -> String:
	_request_serial += 1
	return "%s_%d" % [prefix, _request_serial]


func _broadcast(message: Dictionary) -> void:
	message_broadcast.emit(message)
	for communicator in _members.values().duplicate():
		if is_instance_valid(communicator):
			communicator.receive_message(message)


func _find_duplicate_demolition(target: Node3D, position: Vector3) -> String:
	var key := _target_key(target)
	for request_id in _demolition_tasks.keys():
		var task: Dictionary = _demolition_tasks[request_id]
		if not key.is_empty() and task.get("target_key", "") == key:
			return request_id
		var task_position: Vector3 = task.get("position", Vector3(INF, INF, INF))
		if task_position.is_finite() and position.is_finite() and task_position.distance_to(position) <= demolition_point_merge_radius:
			return request_id
	return ""


func _target_key(target: Node3D) -> String:
	if not is_instance_valid(target):
		return ""
	if target.has_meta("network_device_id"):
		return "network:%s" % str(target.get_meta("network_device_id"))
	if target.is_inside_tree():
		return "path:%s" % str(target.get_path())
	return "instance:%d" % target.get_instance_id()


func _get_member_ai(member_id: String) -> Node:
	var communicator = _members.get(member_id)
	if is_instance_valid(communicator):
		return communicator.owner_ai
	return null


func _is_task_target_active(task: Dictionary) -> bool:
	var target = task.get("target")
	if not is_instance_valid(target):
		return false
	var destroyed_value = target.get("destroyed")
	return destroyed_value == null or not bool(destroyed_value)


func _cleanup_tasks() -> void:
	var now := Time.get_ticks_msec()
	for request_id in _demolition_tasks.keys():
		var task: Dictionary = _demolition_tasks[request_id]
		if not _is_task_target_active(task) and task.get("state", "") in ["open", "claimed"]:
			_demolition_tasks.erase(request_id)
	for request_id in _support_tasks.keys():
		var task: Dictionary = _support_tasks[request_id]
		if float(now - int(task.get("created_msec", now))) / 1000.0 > support_request_lifetime:
			_support_tasks.erase(request_id)


func _cleanup_members() -> void:
	for member_id in _members.keys():
		if not is_instance_valid(_members[member_id]):
			unregister_member(member_id)


func _is_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()


func _debug_message(message: Dictionary) -> void:
	if not debug_enabled:
		return
	var payload: Dictionary = message.get("payload", {})
	var details := ""
	if int(message.get("type", -1)) == Message.Type.DEMOLITION_WARNING:
		details = " radius=%.1fm position=%s" % [
			float(payload.get("radius", demolition_warning_radius)),
			payload.get("position", Vector3.ZERO),
		]
	elif int(message.get("type", -1)) == Message.Type.NAVIGATION_REFRESH:
		details = " position=%s" % payload.get("position", Vector3.ZERO)
	print(
		"[SquadChannel] %s sender=%s request=%s%s"
		% [
			Message.type_name(message.get("type", -1)),
			message.get("sender_member_id", ""),
			message.get("request_id", ""),
			details,
		]
	)
