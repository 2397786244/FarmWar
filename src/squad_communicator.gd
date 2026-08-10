extends Node
class_name SquadCommunicator

## 每个成员统一使用此端点收发消息。AI 不直接操作频道内部任务表。

var member_id := ""
var ai_type := ""
var owner_ai: Node
var channel: Node


func bind(value_owner: Node, value_channel: Node, value_member_id: String, value_ai_type: String) -> void:
	owner_ai = value_owner
	channel = value_channel
	member_id = value_member_id
	ai_type = value_ai_type


func send_message(type: int, payload: Dictionary = {}, reply_to: String = "") -> Dictionary:
	if not is_instance_valid(channel) or not channel.has_method("send_message"):
		return {"accepted": false, "reason": "channel_unavailable"}
	return channel.send_message(member_id, type, payload, reply_to)


func receive_message(message: Dictionary) -> void:
	if not is_instance_valid(owner_ai):
		return
	## 频道会把消息广播给发送者本人，因此在这里统一识别“本 AI 发布的消息”。
	## 这样 Engineer 通过 Squad 业务适配接口直接发出的消息也能被记录，
	## 不需要让 Engineer 绕过 Squad 去操作 Label3D。
	if str(message.get("sender_member_id", "")) == member_id \
			and owner_ai.has_method("record_squad_message"):
		owner_ai.record_squad_message(message)
	if owner_ai.has_method("receive_squad_message"):
		owner_ai.receive_squad_message(message)
