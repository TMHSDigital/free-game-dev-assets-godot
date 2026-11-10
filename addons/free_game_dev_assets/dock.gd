@tool
extends VBoxContainer
## The "Free Assets" dock. Built in code rather than a .tscn so one source
## loads the same in every Godot 4.x the plugin supports.

## Emitted when a feed arrives (from the network or the cache).
signal feed_changed(feed: Dictionary)

const FeedClient := preload("feed_client.gd")

## The loaded feed, or {} before one arrives.
var feed: Dictionary = {}

var _client: Node
var _status: Label
var _refresh: Button


func _ready() -> void:
	var title := Label.new()
	title.text = "Free Game Dev Assets"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var bar := HBoxContainer.new()
	add_child(bar)
	_status = Label.new()
	_status.text = "Loading the catalog…"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	_refresh = Button.new()
	_refresh.text = "Refresh"
	_refresh.tooltip_text = "Fetch the latest catalog now"
	_refresh.disabled = true
	_refresh.pressed.connect(_on_refresh_pressed)
	bar.add_child(_refresh)

	_client = FeedClient.new()
	_client.cache_dir = EditorInterface.get_editor_paths().get_cache_dir()
	add_child(_client)
	_client.loaded.connect(_on_loaded)
	_client.refresh()


func _on_refresh_pressed() -> void:
	_refresh.disabled = true
	_status.text = "Checking for a newer catalog…"
	_client.refresh(true)


func _on_loaded(state: Dictionary) -> void:
	_refresh.disabled = false
	var message := String(state.get("message", ""))
	if state["feed"].is_empty():
		_refresh.text = "Retry"
		_status.text = message
		return
	_refresh.text = "Refresh"
	feed = state["feed"]
	var line := "%d entries, data from %s" % [feed["entries"].size(), feed["version"]]
	_status.text = line if message == "" else "%s\n%s" % [line, message]
	feed_changed.emit(feed)
