class_name HexRRemoteStream
extends RefCounted
## Sharing the headset's view and sound with HexR Remote viewers. On Android it drives the
## HexRRemoteCapture plugin (MediaProjection into H.264 on the video port, the app's own sound
## into AAC on the audio port); everywhere else it reports "unsupported", as the Unity package
## does in the Editor.

var _plugin: Object
var _remote: Node  # HexRRemote, for the capture settings


static func create(remote: Node) -> HexRRemoteStream:
	var s := HexRRemoteStream.new()
	s._remote = remote
	if OS.get_name() == "Android" and Engine.has_singleton("HexRRemoteCapture"):
		s._plugin = Engine.get_singleton("HexRRemoteCapture")
	return s


func is_supported() -> bool:
	return _plugin != null


## Asks the wearer to allow sharing (a system prompt in the headset), then streams.
func start() -> void:
	if _plugin == null:
		return
	_plugin.start(_remote.video_width, _remote.video_height, _remote.video_bitrate_kbps, _remote.video_fps,
			_remote.video_port, _remote.share_sound, _remote.audio_port, _remote.stop_video_after_background_seconds)


func stop() -> void:
	if _plugin:
		_plugin.stop()


## The stream part of the status line.
func read() -> Dictionary:
	if _plugin == null:
		return HexRRemoteProtocol.stream_status(HexRRemoteProtocol.STREAM_UNSUPPORTED, 0, 0, 0, 0,
				"Sharing the view needs the app running on the headset.",
				HexRRemoteProtocol.audio_status(HexRRemoteProtocol.STREAM_UNSUPPORTED))
	return HexRRemoteProtocol.stream_status(_plugin.getState(), _plugin.getPort(), _plugin.getWidth(),
			_plugin.getHeight(), _plugin.getViewerCount(), _plugin.getMessage(),
			HexRRemoteProtocol.audio_status(_plugin.getSoundState(), _plugin.getSoundPort(),
					_plugin.getSoundSampleRate(), _plugin.getSoundChannels(), _plugin.getSoundMessage()))
