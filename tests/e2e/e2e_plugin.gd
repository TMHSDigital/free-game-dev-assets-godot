@tool
extends EditorPlugin
## Dev only. tests/editor_e2e.sh copies this into a throwaway copy of the
## project. It drives the real dock the way a user would (select, Add to
## project, Export credits) and checks the files it writes. Prints
## "e2e ok: N checks" and exits 0, or lists the failures and exits 1.

const Credits := preload("res://addons/free_game_dev_assets/credits.gd")
const TIMEOUT_SEC := 60.0
## Credit required with a line, MIT notice, CC0 no credit.
const PICKS := ["accad-mocap", "beehave", "ox72-dungeon-tileset"]
const MINE_ABOVE := "# My game\n\nMusic and art I made myself.\n\n"
const MINE_BELOW := "\nThanks to everyone who play-tested.\n"

var _elapsed := 0.0
var _started := false
var _passed := 0
var _failed: Array[String] = []


func _process(delta: float) -> void:
	_elapsed += delta
	# A script error inside _run stops it without quitting: give up loudly.
	if _started and _elapsed > TIMEOUT_SEC * 2:
		printerr("e2e: did not finish (see the SCRIPT ERROR above)")
		get_tree().quit(1)
		return
	if _started:
		return
	var dock = EditorInterface.get_base_control().find_child("Free Assets", true, false)
	if dock != null and not dock.feed.is_empty():
		_started = true
		_run(dock)
	elif _elapsed > TIMEOUT_SEC:
		_started = true
		printerr("e2e: the dock did not show a catalog within %d s" % TIMEOUT_SEC)
		get_tree().quit(1)


func eq(label: String, actual, expected) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		_passed += 1
	else:
		_failed.append("%s: expected %s, got %s" % [label, var_to_str(expected), var_to_str(actual)])


func _entry(dock, id: String) -> Dictionary:
	for e in dock.feed["entries"]:
		if e["id"] == id:
			return e
	return {}


func _select(dock, id: String) -> void:
	# The way a click does it: the row's selection handler.
	dock.filters["query"] = ""
	dock.filters["godot"] = false
	dock.filters["project_only"] = false
	dock._rebuild()
	for item in dock._tree.get_root().get_children():
		if item.get_metadata(0) == id:
			item.select(0)
			return
	_failed.append("no row for %s" % id)


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _run(dock) -> void:
	# Start from no list and no CREDITS.md, whatever an earlier run left.
	for path in [Credits.LIST_FILE, Credits.CREDITS_FILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	dock._load_list()
	dock._update_project_row()
	eq("starts with an empty list", dock._project_ids, [])
	eq("export is off with nothing added", dock._export.disabled, true)

	# Add three entries through the details panel.
	for id in PICKS:
		_select(dock, id)
		eq("button offers Add for %s" % id, dock._d_project.text, "Add to project")
		dock._d_project.pressed.emit()
		eq("button offers Remove for %s" % id, dock._d_project.text, "Remove from project")
	var saved := Credits.parse_list(_read(Credits.LIST_FILE))
	eq("list file has the picks, in order", saved["ids"], PICKS)
	eq("list file keeps a snapshot", saved["known"]["accad-mocap"]["credit_line"], _entry(dock, "accad-mocap")["credit_line"])
	eq("project row counts them", dock._project_label.text, "This project uses 3")

	# Only this project's.
	dock.filters["project_only"] = true
	dock.filters["godot"] = false
	dock._rebuild()
	eq("Only this project's shows the picks", dock._tree.get_root().get_child_count(), PICKS.size())
	dock.filters["project_only"] = false
	dock._rebuild()

	# Remove and re-add one.
	_select(dock, "beehave")
	dock._d_project.pressed.emit()
	eq("remove takes it off the list", Credits.parse_list(_read(Credits.LIST_FILE))["ids"], ["accad-mocap", "ox72-dungeon-tileset"])
	dock._d_project.pressed.emit()

	# Export into a CREDITS.md that already has the user's own text.
	var f := FileAccess.open(Credits.CREDITS_FILE, FileAccess.WRITE)
	f.store_string(MINE_ABOVE + "Old notes.\n" + MINE_BELOW)
	f.close()
	dock._export.pressed.emit()
	var first := _read(Credits.CREDITS_FILE)
	eq("export keeps the user's text above", first.begins_with(MINE_ABOVE + "Old notes.\n" + MINE_BELOW), true)
	eq("export adds one block", first.count(Credits.START), 1)
	eq("credit line verbatim", first.contains("- " + _entry(dock, "accad-mocap")["credit_line"]), true)
	eq("MIT entry under notices", first.contains("## Notices to keep with the files"), true)
	eq("CC0 entry under no credit", first.contains("## No credit needed"), true)
	eq("names the catalog version", first.contains(dock.feed["version"]), true)
	eq("says it wrote the file", dock._project_note.text.begins_with("Wrote CREDITS.md"), true)

	# Export again: nothing changes.
	dock._export.pressed.emit()
	eq("second export changes nothing", _read(Credits.CREDITS_FILE), first)
	eq("second export says up to date", dock._project_note.text.begins_with("CREDITS.md is already up to date"), true)

	# Text the user adds outside the markers survives an export.
	f = FileAccess.open(Credits.CREDITS_FILE, FileAccess.WRITE)
	f.store_string(first + "\nOne more thank-you.\n")
	f.close()
	dock._export.pressed.emit()
	eq("text after the block is kept", _read(Credits.CREDITS_FILE), first + "\nOne more thank-you.\n")

	# An entry the catalog dropped, and an id never seen: flagged, not dropped.
	var list := Credits.parse_list(_read(Credits.LIST_FILE))
	list["ids"].append_array(["gone-from-catalog", "typo-id"])
	list["known"]["gone-from-catalog"] = {"name": "Gone Pack", "license": "CC-BY-4.0", "credit_line": "Sounds by Gone (CC BY 4.0)"}
	f = FileAccess.open(Credits.LIST_FILE, FileAccess.WRITE)
	f.store_string(Credits.list_text(list["ids"], list["known"]))
	f.close()
	dock._export.pressed.emit()
	var flagged := _read(Credits.CREDITS_FILE)
	eq("dropped entry flagged", flagged.contains("## No longer listed"), true)
	eq("dropped entry keeps its credit line", flagged.contains("Sounds by Gone (CC BY 4.0)"), true)
	eq("unknown id listed", flagged.contains("`typo-id`"), true)
	eq("note counts them", dock._project_note.text.contains("2 no longer listed"), true)
	eq("project row counts them", dock._project_label.text, "This project uses 5 (2 no longer listed)")
	eq("snapshot of the dropped entry kept", Credits.parse_list(_read(Credits.LIST_FILE))["known"].has("gone-from-catalog"), true)

	# Broken files are reported, never overwritten.
	f = FileAccess.open(Credits.CREDITS_FILE, FileAccess.WRITE)
	f.store_string("Mine\n" + Credits.START + "\nhalf a block\n")
	f.close()
	dock._export.pressed.emit()
	eq("broken markers: file untouched", _read(Credits.CREDITS_FILE), "Mine\n" + Credits.START + "\nhalf a block\n")
	eq("broken markers: says why", dock._project_note.text.contains("markers"), true)
	f = FileAccess.open(Credits.LIST_FILE, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	_select(dock, "beehave")
	dock._d_project.pressed.emit()
	eq("broken list: file untouched", _read(Credits.LIST_FILE), "{not json")
	eq("broken list: export off", dock._export.disabled, true)
	eq("broken list: says why", dock._project_note.text.contains("not valid JSON"), true)

	# A list file that can't be written: the export says so after its result.
	# A folder in its place fails the write on every OS.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Credits.LIST_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Credits.CREDITS_FILE))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(Credits.LIST_FILE))
	dock._on_export()
	eq("unwritable list: export still reported", dock._project_note.text.begins_with("Wrote CREDITS.md"), true)
	eq("unwritable list: says so", dock._project_note.text.ends_with("Could not save free_game_dev_assets.json."), true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Credits.LIST_FILE))

	if _failed.is_empty():
		print("e2e ok: %d checks" % _passed)
		get_tree().quit(0)
	else:
		printerr("e2e failed (%d of %d):" % [_failed.size(), _failed.size() + _passed])
		for x in _failed:
			printerr("  - " + x)
		get_tree().quit(1)
