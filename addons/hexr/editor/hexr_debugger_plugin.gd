@tool
extends EditorDebuggerPlugin
## Carries the HexR dock's commands to a running game and its glove status back, over the
## debugger connection. Works for a game on a headset too (one-click deploy or remote debug).

signal status_received(transport_kind: String, hands: Array)

var _session_id := -1


func _has_capture(capture: String) -> bool:
	return capture == "hexr"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if message == "hexr:status":
		_session_id = session_id
		status_received.emit(data[0], data[1])
		return true
	return false


func is_game_running() -> bool:
	return _session_id >= 0 and get_session(_session_id) != null and get_session(_session_id).is_active()


func send(message: String, data: Array) -> void:
	if is_game_running():
		get_session(_session_id).send_message("hexr:" + message, data)
