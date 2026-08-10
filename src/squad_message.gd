extends RefCounted
class_name SquadMessage

## Squad 公共通信协议。消息使用 Dictionary，便于未来直接做服务器 RPC 序列化；
## Node3D 只用于服务器内部 SET_TARGET，其他公开消息只携带稳定 ID/Vector3。

enum Type {
	SET_TARGET,
	DEMOLITION_REQUEST,
	DEMOLITION_CLAIM,
	DEMOLITION_WARNING,
	ENTRY_FOUND,
	SUPPORT_REQUEST,
	SUPPORT_ACK,
}


static func make(
	message_id: String,
	type: int,
	sender_member_id: String,
	payload: Dictionary = {},
	request_id: String = "",
	reply_to: String = ""
) -> Dictionary:
	return {
		"message_id": message_id,
		"type": type,
		"sender_member_id": sender_member_id,
		"payload": payload.duplicate(),
		"request_id": request_id,
		"reply_to": reply_to,
		"server_time_msec": Time.get_ticks_msec(),
	}


static func type_name(type: int) -> String:
	match type:
		Type.SET_TARGET:
			return "设置target"
		Type.DEMOLITION_REQUEST:
			return "这里需要爆破"
		Type.DEMOLITION_CLAIM:
			return "这里由我来爆破"
		Type.DEMOLITION_WARNING:
			return "这里将要爆破请撤退"
		Type.ENTRY_FOUND:
			return "这里有入口"
		Type.SUPPORT_REQUEST:
			return "我被攻击了请支援"
		Type.SUPPORT_ACK:
			return "正在支援"
	return "未知消息"
