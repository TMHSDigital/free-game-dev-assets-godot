@tool
extends RefCounted
## The project's asset list and its CREDITS.md: reading and writing the two
## files, and what to tell the user about it. No nodes and no editor APIs, so
## the tests can run it headless on scratch paths. The dock shows the notes
## and passes `written` to the editor's filesystem.
##
## Every action reads the list file again first, so edits from git or by hand
## are kept, and a list file that doesn't parse is never overwritten.

const Credits := preload("credits.gd")

var list_path := Credits.LIST_FILE
var credits_path := Credits.CREDITS_FILE

## The list as last read. After a read error these keep the last good list,
## and `error` says what is wrong with the file.
var ids: Array = []
var known: Dictionary = {}
var error := ""
## The files the last action wrote.
var written := PackedStringArray()


func reload() -> void:
	var parsed := Credits.parse_list(_read(list_path))
	error = parsed["error"]
	if error == "":
		ids = parsed["ids"]
		known = parsed["known"]


## How many listed ids the feed no longer has (0 before a feed arrives).
func missing(feed: Dictionary) -> int:
	if feed.is_empty():
		return 0
	var in_feed := {}
	for e in feed.get("entries", []):
		in_feed[e["id"]] = true
	return ids.filter(func(id): return not in_feed.has(id)).size()


## Adds the entry, or removes it if it is listed. Returns a note for the user,
## "" when there is nothing to say.
func toggle(entry: Dictionary) -> String:
	written.clear()
	reload()
	if error != "":
		return error
	var id: String = entry["id"]
	if ids.has(id):
		ids.erase(id)
		known.erase(id)
	else:
		ids.append(id)
		known[id] = Credits.snapshot(entry)
	return "" if _save() else "Could not write %s." % list_path


## Writes the plugin's block into CREDITS.md and refreshes the snapshots.
## Returns the note for the user.
func export_credits(feed: Dictionary) -> String:
	written.clear()
	reload()
	if error != "":
		return error
	var block := Credits.export_block(ids, known, feed)
	var existing := _read(credits_path)
	var merged := Credits.merge(existing, block["text"])
	if not merged["ok"]:
		return merged["error"]
	known = block["known"]
	var list_saved := _save()
	var gone := ""
	if block["missing"] > 0:
		gone = " %d no longer listed: see that section." % block["missing"]
	if not block["changed"].is_empty():
		gone += " Changed since added: %s." % "; ".join(PackedStringArray(block["changed"].map(func(c): return Credits.change_text(c))))
	var note := ""
	if merged["text"] == existing:
		note = "%s is already up to date.%s" % [credits_path.get_file(), gone]
	elif _write(credits_path, merged["text"]):
		note = "Wrote %s for %d assets.%s" % [credits_path.get_file(), ids.size(), gone]
	else:
		note = "Could not write %s." % credits_path
	# After the export result, so a failed list save isn't hidden by it.
	if not list_saved:
		note += " Could not save %s." % list_path.get_file()
	return note


## Adds the catalog entries found in pasted text (see Credits.ids_from_text)
## after the ones already listed. Returns the note for the user.
func import_text(text: String, feed: Dictionary) -> String:
	written.clear()
	reload()
	if error != "":
		return error
	var by_id := {}
	for e in feed.get("entries", []):
		by_id[e["id"]] = e
	var found := Credits.ids_from_text(text, feed)
	var added := 0
	for id in found["ids"]:
		if not ids.has(id):
			ids.append(id)
			known[id] = Credits.snapshot(by_id[id])
			added += 1
	if found["ids"].is_empty() and found["unknown"].is_empty():
		return "Found no catalog entries in the pasted text."
	if added > 0 and not _save():
		return "Could not write %s." % list_path
	var note := "Added %d to the project" % added
	var already: int = found["ids"].size() - added
	if already > 0:
		note += " (%d already in it)" % already
	note += "."
	if not found["unknown"].is_empty():
		note += " %d not in the catalog: %s." % [found["unknown"].size(), ", ".join(PackedStringArray(found["unknown"]))]
	return note


## Saves the list, leaving the file untouched when its text would not change.
func _save() -> bool:
	var text := Credits.list_text(ids, known)
	if FileAccess.file_exists(list_path) and FileAccess.get_file_as_string(list_path) == text:
		return true
	return _write(list_path, text)


func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	written.append(path)
	return true


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
