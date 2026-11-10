@tool
extends VBoxContainer
## The "Free Assets" dock. Built in code rather than a .tscn so one source
## loads the same in every Godot 4.x the plugin supports.


func _ready() -> void:
	var title := Label.new()
	title.text = "Free Game Dev Assets"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var note := Label.new()
	note.text = "The catalog browser is coming. See the plugin's README for progress."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(note)
