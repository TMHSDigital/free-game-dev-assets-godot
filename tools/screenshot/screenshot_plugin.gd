@tool
extends EditorPlugin
## Dev only. tools/screenshot.sh copies this into a throwaway copy of the
## project, so it never runs in the repo or in a user's project.
##
## Waits for the Free Assets dock to show a catalog, brings its tab to the
## front, types the search (without saving it to the user's filter settings),
## saves the dock as a PNG and quits.
##
## Settings come from environment variables set by the script:
##   FGDA_SHOT_OUT     absolute path of the PNG to write (required)
##   FGDA_SHOT_QUERY   search text, "" for none
##   FGDA_SHOT_SELECT  id of the entry to select, "" for none
##   FGDA_SHOT_HEIGHT  pixels of the dock to keep from the top, 0 for all
##   FGDA_SHOT_PROJECT comma-separated ids to put on the project's asset list
##                     and show with "Only this project's", "" for none
##   FGDA_SHOT_EXPORT  "1" to press Export credits before the shot
##
## Exit codes: 0 saved, 1 failed, 2 saved but some licence text is cut short.

const TIMEOUT_SEC := 60.0
## Seconds to wait after the feed arrives, so the editor finishes its own
## first-frame layout.
const SETTLE_SEC := 3.0

var _elapsed := 0.0
var _ready_at := -1.0
var _started := false


func _process(delta: float) -> void:
	if _started:
		return
	_elapsed += delta
	var dock = EditorInterface.get_base_control().find_child("Free Assets", true, false)
	var loaded: bool = dock != null and not dock.feed.is_empty()
	if loaded and _ready_at < 0.0:
		_ready_at = _elapsed
	if loaded and _elapsed - _ready_at >= SETTLE_SEC:
		_started = true
		_capture(dock)
	elif _elapsed > TIMEOUT_SEC:
		_started = true
		printerr("screenshot: the dock did not show a catalog within %d s (offline with no cached copy?)" % TIMEOUT_SEC)
		get_tree().quit(1)


func _capture(dock) -> void:  # untyped: reaches into dock.gd's members
	var out := OS.get_environment("FGDA_SHOT_OUT")
	if out == "":
		printerr("screenshot: FGDA_SHOT_OUT is not set")
		get_tree().quit(1)
		return

	# Bring the dock's tab to the front. The dock may sit in a wrapper
	# (EditorDock in Godot 4.6+), so climb to the TabContainer.
	var node: Node = dock
	while node.get_parent() and not (node.get_parent() is TabContainer):
		node = node.get_parent()
	if node.get_parent():
		node.get_parent().current_tab = node.get_index()

	# Set the search directly rather than through the UI, which would save it.
	var query := OS.get_environment("FGDA_SHOT_QUERY")
	dock._search.text = query
	dock.filters["query"] = query

	# The asset list lives in the throwaway project, so writing it is safe.
	var project := OS.get_environment("FGDA_SHOT_PROJECT")
	if project != "":
		var by_id := {}
		for e in dock.feed["entries"]:
			by_id[e["id"]] = e
		var ids: Array = []
		var known := {}
		for id in project.split(",", false):
			ids.append(id)
			if by_id.has(id):
				known[id] = dock.Credits.snapshot(by_id[id])
		var f := FileAccess.open(dock.Credits.LIST_FILE, FileAccess.WRITE)
		f.store_string(dock.Credits.list_text(ids, known))
		f.close()
		dock._list.reload()
		dock.filters["project_only"] = true
		dock._project_only.set_pressed_no_signal(true)
	dock._rebuild()
	dock._update_project_row()
	if OS.get_environment("FGDA_SHOT_EXPORT") == "1":
		dock._export.pressed.emit()

	var select := OS.get_environment("FGDA_SHOT_SELECT")
	if select != "":
		var found := false
		for item in dock._tree.get_root().get_children():
			if item.get_metadata(0) == select:
				item.select(0)
				dock._tree.scroll_to_item(item)
				found = true
				break
		if not found:
			printerr("screenshot: no row with id %s in the list (is it filtered out?)" % select)
			get_tree().quit(1)
			return
	for i in 15:
		await get_tree().process_frame

	var cut: PackedStringArray = _cut_licences(dock._tree)
	var img := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	var r: Rect2 = dock.get_global_rect()
	var tab_bar := 40.0 * EditorInterface.get_editor_scale()
	var height := r.size.y + tab_bar + 6.0
	var keep := OS.get_environment("FGDA_SHOT_HEIGHT").to_int()
	if keep > 0:
		height = minf(height, keep)
	var region := Rect2i(Rect2(r.position.x - 6.0, r.position.y - tab_bar, r.size.x + 12.0, height))
	region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.get_region(region).save_png(out)
	if err != OK:
		printerr("screenshot: could not write %s (error %d)" % [out, err])
		get_tree().quit(1)
		return
	print("screenshot: saved %s (%dx%d), %s" % [out, region.size.x, region.size.y, dock._count.text])
	if not cut.is_empty():
		printerr("screenshot: licence text cut short on %d rows, e.g. %s" % [cut.size(), ", ".join(cut.slice(0, 3))])
		get_tree().quit(2)
		return
	get_tree().quit(0)


## Licence ids wider than the licence column, among the rows shown.
func _cut_licences(tree: Tree) -> PackedStringArray:
	var font := tree.get_theme_font("font")
	var size := tree.get_theme_font_size("font_size")
	var room := tree.get_column_width(2) - 4.0 * EditorInterface.get_editor_scale()
	var cut := PackedStringArray()
	var root := tree.get_root()
	if root == null:
		return cut
	for item in root.get_children():
		var text := item.get_text(2)
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room and not cut.has(text):
			cut.append(text)
	return cut
