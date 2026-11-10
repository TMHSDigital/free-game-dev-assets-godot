@tool
extends RefCounted
## The last good feed and its HTTP validators, kept on disk in the editor's
## cache folder (never in the user's project). Every function takes the folder,
## so tests can point it at a scratch directory.

const FEED_FILE := "free_game_dev_assets_feed.json"
const META_FILE := "free_game_dev_assets_feed.meta.json"

## Refresh on its own at most once a day.
const MAX_AGE_SEC := 24 * 60 * 60


static func read_text(dir: String) -> String:
	var path := dir.path_join(FEED_FILE)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## {"etag": String, "last_modified": String, "fetched_at": float}, or {} when there is none.
static func read_meta(dir: String) -> Dictionary:
	var path := dir.path_join(META_FILE)
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


## Saves a feed that parsed cleanly, with its validators. Returns false if it could not be written.
static func write(dir: String, text: String, meta: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	# Write beside the old copy and swap, so a crash mid-write keeps the old one.
	var path := dir.path_join(FEED_FILE)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		return false
	return write_meta(dir, meta)


static func write_meta(dir: String, meta: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(META_FILE), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(meta))
	f.close()
	return true


## True when the cached copy was fetched (or confirmed by a 304) less than a day ago.
## A clock that went backwards counts as stale.
static func is_fresh(meta: Dictionary, now: float) -> bool:
	var at = meta.get("fetched_at")
	if typeof(at) != TYPE_FLOAT and typeof(at) != TYPE_INT:
		return false
	var age := now - float(at)
	return age >= 0.0 and age < MAX_AGE_SEC
