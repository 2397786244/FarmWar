extends PanelContainer
class_name TeamChatPanel

const MAX_MESSAGE_CHARACTERS := 256
const MAX_HISTORY_MESSAGES := 100
const MODE_CLOSED := "closed"
const MODE_TEAM := "team"
const MODE_ALL := "all"

var player: GamePlayer = null
var messages: Array[String] = []
var chat_mode := MODE_CLOSED

@onready var history: RichTextLabel = $Margin/VBox/History
@onready var input: LineEdit = $Margin/VBox/Input


func _ready() -> void:
	visible = true
	input.visible = false
	_set_chat_mouse_enabled(false)
	input.max_length = MAX_MESSAGE_CHARACTERS
	if not MultiplayerNetwork.team_chat_message_received.is_connected(_on_team_chat_message_received):
		MultiplayerNetwork.team_chat_message_received.connect(_on_team_chat_message_received)
	if not GameAuthority.team_chat_message_ready.is_connected(_on_team_chat_message_received):
		GameAuthority.team_chat_message_ready.connect(_on_team_chat_message_received)


func bind_player(value: GamePlayer) -> void:
	player = value


func is_chat_open() -> bool:
	return chat_mode != MODE_CLOSED


func is_text_input_focused() -> bool:
	return input.visible and input.has_focus()


func is_modified_talk_event(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or not (key_event.ctrl_pressed or key_event.meta_pressed):
		return false
	for binding: InputEvent in InputMap.action_get_events("talk"):
		if not binding is InputEventKey:
			continue
		var bound_key := binding as InputEventKey
		if bound_key.physical_keycode != 0 and bound_key.physical_keycode == key_event.physical_keycode:
			return true
		if bound_key.keycode != 0 and bound_key.keycode == key_event.keycode:
			return true
	return false


func toggle_chat() -> void:
	match chat_mode:
		MODE_CLOSED:
			open_chat(MODE_TEAM)
		MODE_TEAM:
			open_chat(MODE_ALL)
		_:
			close_chat()


func open_chat(mode := MODE_TEAM) -> void:
	chat_mode = MODE_ALL if mode == MODE_ALL else MODE_TEAM
	input.visible = true
	_set_chat_mouse_enabled(true)
	input.placeholder_text = "[All] 输入消息；Ctrl/Cmd+Y 切换" if chat_mode == MODE_ALL else \
		"[Team] 输入消息；Ctrl/Cmd+Y 切换"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_focus_input")


func close_chat() -> void:
	if chat_mode == MODE_CLOSED:
		return
	chat_mode = MODE_CLOSED
	input.visible = false
	_set_chat_mouse_enabled(false)
	input.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_chat_mouse_enabled(enabled: bool) -> void:
	# Chat history is informational and may overlap inventory/appliance pages.
	# Only the visible text input owns mouse events while chat entry is active.
	_set_descendant_mouse_filter(self, Control.MOUSE_FILTER_IGNORE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(history):
		history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(input):
		input.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _set_descendant_mouse_filter(node: Node, filter: Control.MouseFilter) -> void:
	for child: Node in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = filter
		_set_descendant_mouse_filter(child, filter)


func submit_current_text() -> void:
	if chat_mode == MODE_CLOSED:
		return
	var message := input.text.strip_edges()
	if message.is_empty():
		_focus_input()
		return
	message = message.substr(0, MAX_MESSAGE_CHARACTERS)
	input.clear()
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_team_chat(message, chat_mode)
	elif is_instance_valid(player):
		GameAuthority.local_team_chat(player.authority_peer_id, message, chat_mode)
	_focus_input()


func _focus_input() -> void:
	if chat_mode != MODE_CLOSED and is_instance_valid(input):
		input.grab_focus()
		input.caret_column = input.text.length()


func _on_team_chat_message_received(message: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	var recipient_peer_id := int(message.get("recipient_peer_id", 0))
	if recipient_peer_id > 0 and recipient_peer_id != player.authority_peer_id:
		return
	var scope := str(message.get("scope", MODE_TEAM))
	if recipient_peer_id <= 0 and scope != MODE_ALL and str(message.get("team", "")) != player.team:
		return
	var text := str(message.get("text", "")).strip_edges()
	if text.is_empty():
		return
	var line := "[System] %s" % text if bool(message.get("system", false)) else \
		"[%s] %d: %s" % ["All" if scope == MODE_ALL else "Team", int(message.get("sender_peer_id", 0)), text]
	messages.append(line)
	if messages.size() > MAX_HISTORY_MESSAGES:
		messages.pop_front()
	history.text = "\n".join(messages)
	call_deferred("_scroll_history_to_bottom")
	if bool(message.get("show_notice", false)) and player.has_method("show_gameplay_notice"):
		player.call("show_gameplay_notice", text)


func _scroll_history_to_bottom() -> void:
	if is_instance_valid(history):
		history.scroll_to_line(maxi(0, history.get_line_count() - 1))
