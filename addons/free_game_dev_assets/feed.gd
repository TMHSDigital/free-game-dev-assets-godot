@tool
extends RefCounted
## Parses and checks plugin-feed.json from the Free Game Dev Assets catalog.
## No nodes and no editor APIs, so the tests can run it headless.
##
## The feed's `format` goes up only on a breaking change; new keys can appear
## at any time and are ignored. See
## https://github.com/TMHSDigital/Free-Game-Dev-Assets/blob/main/docs/data.md#plugin-feed

const URL := "https://tmhsdigital.github.io/Free-Game-Dev-Assets/plugin-feed.json"
const DEFAULT_SITE_URL := "https://tmhsdigital.github.io/Free-Game-Dev-Assets/"

## The highest feed format this plugin understands.
const SUPPORTED_FORMAT := 1

const _ENTRY_STRINGS := ["id", "name", "url", "page", "category", "license"]
const _ENTRY_ARRAYS := ["formats", "tags", "works_in", "made_for"]


## Parses feed text. Returns a Dictionary:
##   ok: bool, error: String, too_new: bool,
##   feed: Dictionary (the parsed feed when ok), dropped: int (malformed entries left out).
static func parse(text: String) -> Dictionary:
	var out := {"ok": false, "error": "", "too_new": false, "feed": {}, "dropped": 0}
	var data = quiet_json(text)
	if typeof(data) != TYPE_DICTIONARY:
		out["error"] = "the catalog feed is not valid JSON"
		return out
	var fmt = data.get("format")
	# JSON numbers arrive as floats.
	if typeof(fmt) != TYPE_INT and typeof(fmt) != TYPE_FLOAT:
		out["error"] = "the catalog feed has no format number"
		return out
	if int(fmt) > SUPPORTED_FORMAT:
		out["too_new"] = true
		out["error"] = "the catalog feed (format %d) is newer than this plugin (format %d): update the plugin" % [int(fmt), SUPPORTED_FORMAT]
		return out
	if typeof(data.get("version")) != TYPE_STRING or typeof(data.get("entries")) != TYPE_ARRAY:
		out["error"] = "the catalog feed is missing its version or entries"
		return out

	var kept: Array = []
	for e in data["entries"]:
		if _valid_entry(e):
			kept.append(e)
		else:
			out["dropped"] += 1
	data["entries"] = kept
	for key in ["categories", "licenseFamilies", "engines"]:
		if typeof(data.get(key)) != TYPE_DICTIONARY:
			data[key] = {}
	var site = data.get("siteUrl")
	if typeof(site) != TYPE_STRING or not String(site).begins_with("https://"):
		data["siteUrl"] = DEFAULT_SITE_URL
	out["ok"] = true
	out["feed"] = data
	return out


## Parses JSON, or returns null, without printing an engine error: a Wi-Fi
## login page that answers 200 with HTML should not put red text in the
## user's Output panel.
static func quiet_json(text: String):
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _valid_entry(e) -> bool:
	if typeof(e) != TYPE_DICTIONARY:
		return false
	for key in _ENTRY_STRINGS:
		if typeof(e.get(key)) != TYPE_STRING:
			return false
	for key in _ENTRY_ARRAYS:
		if typeof(e.get(key)) != TYPE_ARRAY:
			return false
	return true
