@tool
extends EditorPlugin
## Adds the "Free Assets" dock. Everything the dock does lives in dock.gd;
## this file only adds it and takes it away again, so turning the plugin off
## and on leaves nothing behind.

const Dock := preload("dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Free Assets"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	print_verbose("free_game_dev_assets: dock added")


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
	print_verbose("free_game_dev_assets: dock removed")
