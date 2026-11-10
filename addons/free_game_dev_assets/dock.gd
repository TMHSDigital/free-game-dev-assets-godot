@tool
extends VBoxContainer
## The "Free Assets" dock. Built in code rather than a .tscn so one source
## loads the same in every Godot 4.x the plugin supports.

## Emitted when a feed arrives (from the network or the cache).
signal feed_changed(feed: Dictionary)
## Emitted when a row is selected; carries the entry's id.
signal entry_selected(id: String)

const FeedClient := preload("feed_client.gd")
const Browse := preload("browse.gd")
const Details := preload("entry_details.gd")
const Credits := preload("credits.gd")
const ProjectList := preload("project_list.gd")

## Typing waits this long after the last key before the list updates.
const SEARCH_DELAY_SEC := 0.2

## Badge colours by licence family. Translucent so the licence text on top
## reads in light and dark editor themes; the text carries the meaning.
const FAMILY_COLORS := {
	"public-domain": Color(0.30, 0.75, 0.40, 0.35),
	"cc-by": Color(0.30, 0.55, 0.90, 0.35),
	"permissive": Color(0.25, 0.70, 0.75, 0.35),
	"copyleft": Color(0.90, 0.60, 0.20, 0.35),
	"custom": Color(0.85, 0.35, 0.35, 0.35),
	"mixed": Color(0.55, 0.55, 0.55, 0.35),
}

enum Col { NAME, CATEGORY, LICENSE }

## The loaded feed, or {} before one arrives.
var feed: Dictionary = {}
## The current filter state (see Browse.default_filters()).
var filters: Dictionary = Browse.default_filters()

var _client: Node
var _status: Label
var _refresh: Button
var _search: LineEdit
var _search_timer: Timer
var _category: OptionButton
var _family: OptionButton
var _format: OptionButton
var _commercial: CheckBox
var _no_credit: CheckBox
var _godot: CheckBox
var _count: Label
var _tree: Tree
var _settings_path := ""

# Details panel.
var _selected: Dictionary = {}
var _shown_by_id: Dictionary = {}
var _d_project: Button

# The project's asset list (res://free_game_dev_assets.json).
var _list := ProjectList.new()
var _project_label: Label
var _project_only: CheckBox
var _export: Button
var _import: Button
var _import_dialog: ConfirmationDialog
var _import_text: TextEdit
var _project_note: Label
var _details_hint: Label
var _details: VBoxContainer
var _d_name: Label
var _d_facts: GridContainer
var _d_summary: Label
var _d_open_source: Button
var _d_open_page: Button
var _d_copy: Button
var _d_action_note: Label
var _d_verified: Label


func _ready() -> void:
	_settings_path = EditorInterface.get_editor_paths().get_config_dir().path_join(Browse.SETTINGS_FILE)
	filters = Browse.load_filters(_settings_path)
	_list.reload()

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

	_build_filters()

	_build_project_row()

	_count = Label.new()
	add_child(_count)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.set_column_title(Col.NAME, "Name")
	_tree.set_column_title(Col.CATEGORY, "Category")
	_tree.set_column_title(Col.LICENSE, "Licence")
	_tree.set_column_expand(Col.NAME, true)
	_tree.set_column_expand(Col.CATEGORY, false)
	_tree.set_column_expand(Col.LICENSE, false)
	_tree.item_selected.connect(_on_item_selected)

	# The list above, the selected entry's details below; drag to resize.
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(_tree)
	split.add_child(_build_details())

	_client = FeedClient.new()
	_client.cache_dir = EditorInterface.get_editor_paths().get_cache_dir()
	add_child(_client)
	_client.loaded.connect(_on_loaded)
	_client.refresh()


func _build_details() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 160 * EditorInterface.get_editor_scale()
	# Share the height with the list: list 55%, details 45%, until dragged.
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.8
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_details_hint = Label.new()
	_details_hint.text = "Select an entry to see its licence and links."
	_details_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_details_hint)

	_details = VBoxContainer.new()
	_details.visible = false
	box.add_child(_details)

	_d_name = Label.new()
	_d_name.add_theme_font_size_override("font_size", 15)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(_d_name)

	_d_facts = GridContainer.new()
	_d_facts.columns = 2
	_details.add_child(_d_facts)

	var actions := HFlowContainer.new()
	_details.add_child(actions)
	_d_project = _action(actions, "Add to project", "Add this entry to the project's asset list, which Export credits writes into CREDITS.md", _on_toggle_project)
	_d_open_source = _action(actions, "Open source", "Open the source's own page in your browser", _on_open_source)
	_d_open_page = _action(actions, "Catalog page", "Open the catalog's page for this entry, where the licence is quoted", _on_open_page)
	_d_copy = _action(actions, "Copy credit line", "Copy the recorded credit line to the clipboard", _on_copy_credit)

	_d_action_note = Label.new()
	_d_action_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(_d_action_note)

	_d_verified = Label.new()
	_d_verified.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_verified.modulate = Color(1, 1, 1, 0.7)
	_details.add_child(_d_verified)

	# Last, so a long summary never pushes the actions out of view.
	_d_summary = Label.new()
	_d_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(_d_summary)
	return scroll


func _action(parent: Control, text: String, tip: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _show_details(e: Dictionary) -> void:
	_selected = e
	_details_hint.visible = e.is_empty()
	_details.visible = not e.is_empty()
	if e.is_empty():
		return
	_d_name.text = String(e["name"])
	for child in _d_facts.get_children():
		_d_facts.remove_child(child)
		child.queue_free()
	var credit := Details.credit(e)
	var formats: Array = e.get("formats", [])
	var facts := []
	if typeof(e.get("publisher")) == TYPE_STRING and e["publisher"] != "":
		facts.append(["Publisher", e["publisher"]])
	facts.append_array([
		["Licence", Details.licence_text(e)],
		["Commercial use", Details.commercial_text(e.get("commercial"))],
		["Credit", credit["text"]],
		["Formats", ", ".join(PackedStringArray(formats)) if not formats.is_empty() else "Not recorded"],
		["Verified", e["verified"] if typeof(e.get("verified")) == TYPE_STRING else "Not recorded"],
	])
	if e.get("status") == "needs-review":
		facts.append(["Status", "Needs review: the catalog page says what is still open"])
	for fact in facts:
		var k := Label.new()
		k.text = fact[0]
		k.modulate = Color(1, 1, 1, 0.7)
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_d_facts.add_child(k)
		var v := Label.new()
		v.text = String(fact[1])
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_d_facts.add_child(v)
	_d_summary.text = String(e["summary"]) if typeof(e.get("summary")) == TYPE_STRING else ""
	_d_summary.visible = _d_summary.text != ""

	var notes := PackedStringArray()
	_d_open_source.disabled = Details.source_url(e) == ""
	if _d_open_source.disabled:
		notes.append("The source link isn't https, so the plugin won't open it. The catalog page links to it.")
	_d_open_page.disabled = Details.catalog_page_url(feed, e) == ""
	_d_copy.disabled = not credit["can_copy"]
	if credit["note"] != "":
		notes.append(credit["note"])
	var changed := Credits.changes([e["id"]], _list.known, feed) if _list.ids.has(e["id"]) else []
	if not changed.is_empty():
		var c: Dictionary = changed[0]
		var what := PackedStringArray()
		if not c["license"].is_empty():
			what.append("the licence was %s" % Credits.or_none(c["license"][0]))
		if not c["credit_line"].is_empty():
			what.append("the credit line was \"%s\"" % Credits.or_none(c["credit_line"][0]))
		notes.append("Changed since you added it: %s. Export credits writes the new terms." % " and ".join(what))
	_d_action_note.text = "\n".join(notes)
	_d_action_note.visible = not notes.is_empty()
	_d_verified.text = Details.verified_note(e)
	_update_project_button()


func _on_open_source() -> void:
	var url := Details.source_url(_selected)
	if url != "":
		OS.shell_open(url)


func _on_open_page() -> void:
	var url := Details.catalog_page_url(feed, _selected)
	if url != "":
		OS.shell_open(url)


func _on_copy_credit() -> void:
	var credit := Details.credit(_selected)
	if not credit["can_copy"]:
		return
	DisplayServer.clipboard_set(credit["line"])
	var note := "Copied the credit line."
	if credit["fill_in"]:
		note += " Fill in the {…} parts after pasting."
	_d_action_note.text = note
	_d_action_note.visible = true


func _build_filters() -> void:
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, tags, publisher…"
	_search.clear_button_enabled = true
	_search.text = filters["query"]
	_search.text_changed.connect(func(_t): _search_timer.start())
	add_child(_search)

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY_SEC
	_search_timer.timeout.connect(func(): _set_filter("query", _search.text.strip_edges()))
	add_child(_search_timer)

	var row := HBoxContainer.new()
	add_child(row)
	_category = OptionButton.new()
	_category.tooltip_text = "Category"
	_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category.clip_text = true
	_category.item_selected.connect(func(i): _set_filter("category", String(_category.get_item_metadata(i))))
	row.add_child(_category)
	_family = OptionButton.new()
	_family.tooltip_text = "Licence family"
	_family.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_family.clip_text = true
	_family.item_selected.connect(func(i): _set_filter("license_family", String(_family.get_item_metadata(i))))
	row.add_child(_family)
	_format = OptionButton.new()
	_format.tooltip_text = "File format"
	_format.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_format.clip_text = true
	_format.item_selected.connect(func(i): _set_filter("format", String(_format.get_item_metadata(i))))
	row.add_child(_format)
	_fill_options()

	var checks := HFlowContainer.new()
	add_child(checks)
	_godot = _check(checks, "Works in Godot", "godot", "Only entries that can be used in Godot")
	_commercial = _check(checks, "Commercial use OK", "commercial", "Only entries whose licence allows commercial use")
	_no_credit = _check(checks, "No credit needed", "no_credit", "Only entries that don't require attribution")


func _check(parent: Control, text: String, key: String, tip: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.tooltip_text = tip
	box.button_pressed = filters[key]
	box.toggled.connect(func(on): _set_filter(key, on))
	parent.add_child(box)
	return box


## Fills the category and licence family menus from the feed's label maps,
## and the format menu from the formats its entries use.
## A saved choice the feed no longer has falls back to "any".
func _fill_options() -> void:
	_fill_option(_category, "All categories", feed.get("categories", {}), "category")
	_fill_option(_family, "All licences", feed.get("licenseFamilies", {}), "license_family")
	_fill_option(_format, "All formats", Browse.format_labels(feed.get("entries", [])), "format")


func _fill_option(menu: OptionButton, any_label: String, labels: Dictionary, key: String) -> void:
	menu.clear()
	menu.add_item(any_label)
	menu.set_item_metadata(0, "")
	var selected := 0
	for id in labels:
		menu.add_item(String(labels[id]))
		var i := menu.item_count - 1
		menu.set_item_metadata(i, String(id))
		if id == filters[key]:
			selected = i
	menu.select(selected)
	# Only drop a saved choice once a feed is here to say it's gone.
	if selected == 0 and filters[key] != "" and not feed.is_empty():
		_set_filter(key, "")


func _set_filter(key: String, value) -> void:
	if filters.get(key) == value:
		return
	filters[key] = value
	Browse.save_filters(_settings_path, filters)
	_rebuild()


func _rebuild() -> void:
	_tree.clear()
	_shown_by_id.clear()
	var entries: Array = feed.get("entries", [])
	if entries.is_empty():
		_count.text = ""
		_show_details({})
		return
	var total := entries.size()
	if filters.get("project_only", false):
		entries = entries.filter(func(e): return _list.ids.has(e["id"]))
	var shown := Browse.apply(entries, filters)
	_count.text = "Showing %d of %d" % [shown.size(), total]
	var categories: Dictionary = feed.get("categories", {})
	var families: Dictionary = feed.get("licenseFamilies", {})
	var keep_id: String = _selected.get("id", "")
	var keep: TreeItem = null
	var changed := {}
	for c in Credits.changes(_list.ids, _list.known, feed):
		changed[c["id"]] = true
	var root := _tree.create_item()
	for e in shown:
		var item := _tree.create_item(root)
		_shown_by_id[e["id"]] = e
		if e["id"] == keep_id:
			keep = item
		var name := String(e["name"])
		if _list.ids.has(e["id"]):
			name = "✓ " + name
		if changed.has(e["id"]):
			name += "  (changed since added)"
		if e.get("status") == "needs-review":
			name += "  (needs review)"
		item.set_text(Col.NAME, name)
		item.set_tooltip_text(Col.NAME, _tooltip(e))
		item.set_metadata(Col.NAME, e["id"])
		item.set_text(Col.CATEGORY, String(categories.get(e["category"], e["category"])))
		item.set_text(Col.LICENSE, String(e["license"]))
		var family = e.get("licenseFamily", "")
		var licence_tip := String(e["license"])
		if families.has(family):
			licence_tip += "\n" + String(families[family])
		item.set_tooltip_text(Col.LICENSE, licence_tip)
		if FAMILY_COLORS.has(family):
			item.set_custom_bg_color(Col.LICENSE, FAMILY_COLORS[family])
	# Keep the selected entry selected while it is still in the list; the
	# details then show its data from this feed.
	if keep:
		keep.select(Col.NAME)
		_tree.scroll_to_item(keep)
		_show_details(_shown_by_id[keep_id])
	else:
		_show_details({})


func _tooltip(e: Dictionary) -> String:
	var lines: PackedStringArray = [String(e["name"])]
	if typeof(e.get("publisher")) == TYPE_STRING:
		lines.append("by " + e["publisher"])
	if typeof(e.get("summary")) == TYPE_STRING:
		lines.append(e["summary"])
	if e.get("status") == "needs-review":
		lines.append("The catalog marks this entry as needing review.")
	return "\n".join(lines)


func _on_item_selected() -> void:
	var item := _tree.get_selected()
	if item:
		var id := String(item.get_metadata(Col.NAME))
		_show_details(_shown_by_id.get(id, {}))
		entry_selected.emit(id)


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
	var line := "Catalog %s" % feed["version"]
	_status.text = line if message == "" else "%s\n%s" % [line, message]
	_fill_options()
	_fit_columns()
	_list.reload()
	_rebuild()
	_update_project_row()
	feed_changed.emit(feed)


## Sizes the category and licence columns to their widest text in this feed,
## so no licence id is cut short at any editor scale.
func _fit_columns() -> void:
	var font := _tree.get_theme_font("font")
	var size := _tree.get_theme_font_size("font_size")
	var pad := 16.0 * EditorInterface.get_editor_scale()
	var widest := {Col.CATEGORY: 0.0, Col.LICENSE: 0.0}
	for label in feed.get("categories", {}).values():
		widest[Col.CATEGORY] = maxf(widest[Col.CATEGORY], font.get_string_size(String(label), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	for e in feed.get("entries", []):
		widest[Col.LICENSE] = maxf(widest[Col.LICENSE], font.get_string_size(String(e["license"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	for col in widest:
		_tree.set_column_custom_minimum_width(col, ceili(widest[col] + pad))


# --- The project's asset list and CREDITS.md ---------------------------------

func _build_project_row() -> void:
	var row := HFlowContainer.new()
	add_child(row)
	_project_label = Label.new()
	_project_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_project_label)
	_project_only = _check(row, "Only this project's", "project_only", "Show only the entries in this project's asset list")
	_export = Button.new()
	_export.text = "Export credits"
	_export.tooltip_text = "Write what this project's assets owe into %s. Only the part between the plugin's markers is replaced." % Credits.CREDITS_FILE
	_export.pressed.connect(_on_export)
	row.add_child(_export)
	_import = Button.new()
	_import.text = "Import…"
	_import.tooltip_text = "Add entries to this project's asset list from catalog page links, the website shortlist's licence-changes.opml, or entry ids"
	_import.pressed.connect(_on_import_pressed)
	row.add_child(_import)
	_project_note = Label.new()
	_project_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_project_note.visible = false
	add_child(_project_note)
	_update_project_row()


## Shows the result of a list action (a ProjectList note), tells the editor
## about the files it wrote, and refreshes everything that shows the list.
func _after_list_action(note: String) -> void:
	for path in _list.written:
		EditorInterface.get_resource_filesystem().update_file(path)
	_note(note)
	_rebuild()
	_update_project_row()


func _update_project_row() -> void:
	if _project_label == null:
		return
	if _list.error != "":
		_project_label.text = "Asset list: error"
		_note(_list.error)
	else:
		var missing := _list.missing(feed)
		var text := "This project uses %d" % _list.ids.size()
		var flags := PackedStringArray()
		if missing > 0:
			flags.append("%d no longer listed" % missing)
		var changed := Credits.changes(_list.ids, _list.known, feed).size()
		if changed > 0:
			flags.append("%d changed since added" % changed)
		if not flags.is_empty():
			text += " (%s)" % ", ".join(flags)
		_project_label.text = text
		_project_label.tooltip_text = "Rows marked \"changed since added\" show what changed when selected. Export credits writes the new terms." if changed > 0 else ""
	_export.disabled = feed.is_empty() or _list.error != "" or _list.ids.is_empty()
	_import.disabled = feed.is_empty() or _list.error != ""
	_update_project_button()


func _on_import_pressed() -> void:
	if _import_dialog == null:
		_import_dialog = ConfirmationDialog.new()
		_import_dialog.title = "Import into this project's asset list"
		_import_dialog.ok_button_text = "Import"
		var box := VBoxContainer.new()
		var hint := Label.new()
		hint.text = "Paste catalog page links, the licence-changes.opml exported from the website's shortlist, or entry ids."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 480 * EditorInterface.get_editor_scale()
		box.add_child(hint)
		_import_text = TextEdit.new()
		_import_text.custom_minimum_size = Vector2(480, 220) * EditorInterface.get_editor_scale()
		box.add_child(_import_text)
		_import_dialog.add_child(box)
		_import_dialog.confirmed.connect(func(): _import_ids(_import_text.text))
		add_child(_import_dialog)
	_import_text.text = ""
	_import_dialog.popup_centered()
	_import_text.grab_focus()


## Adds the catalog entries found in `text` to the project's list, after
## the ones already there.
func _import_ids(text: String) -> void:
	_after_list_action(_list.import_text(text, feed))


func _update_project_button() -> void:
	if _d_project == null or _selected.is_empty():
		return
	var inside := _list.ids.has(_selected["id"])
	_d_project.text = "Remove from project" if inside else "Add to project"
	_d_project.disabled = _list.error != ""


func _note(text: String) -> void:
	_project_note.text = text
	_project_note.visible = text != ""


func _on_toggle_project() -> void:
	if _selected.is_empty():
		return
	_after_list_action(_list.toggle(_selected))


func _on_export() -> void:
	# The rebuild also clears "changed since added": export refreshes the snapshots.
	_after_list_action(_list.export_credits(feed))
