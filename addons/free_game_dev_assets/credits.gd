@tool
extends RefCounted
## The project's asset list and its CREDITS.md block.
## No nodes and no editor APIs, so the tests can run it headless.
##
## owes() and credits_file() are a line-for-line port of the catalog
## website's site/lib/owes.mjs (owes, creditsFile), so the file says what
## the website's shortlist export says. CI runs both on the live catalog and
## fails if they differ (tests/check_credits_match_site.sh).

## The asset list, in the project so it is committed and shared.
const LIST_FILE := "res://free_game_dev_assets.json"
const CREDITS_FILE := "res://CREDITS.md"
const LIST_FORMAT := 1

const Details := preload("entry_details.gd")

const START := "<!-- free-game-dev-assets:start -->"
const END := "<!-- free-game-dev-assets:end -->"

const FILL_IN_HEADER := "Fill in every {…} field below before you ship."
## What the snapshot keeps per entry, so a line survives the entry leaving the catalog.
const _KNOWN_KEYS := ["name", "license", "credit_line"]


# --- Port of owes.mjs ----------------------------------------------------------

## What the picked entries owe. Each group is an Array of entries, in pick
## order; an entry picked twice is listed once.
static func owes(picked: Array) -> Dictionary:
	var seen := {}
	var items: Array = []
	for e in picked:
		if not seen.has(e["id"]):
			seen[e["id"]] = true
			items.append(e)
	var out := {"credits": [], "notices": [], "noCredit": [], "unclear": [], "perFile": [], "openQuestions": []}
	for e in items:
		var credit = e.get("attribution_required")
		var is_true: bool = typeof(credit) == TYPE_BOOL and credit
		var is_false: bool = typeof(credit) == TYPE_BOOL and not credit
		var notice: bool = typeof(e.get("attributionClass")) == TYPE_STRING and e["attributionClass"] == "notice"
		if is_true:
			out["credits"].append(e)
		if notice:
			out["notices"].append(e)
		if is_false and not notice:
			out["noCredit"].append(e)
		if not is_true and not is_false:
			out["unclear"].append(e)
		if typeof(e.get("commercial")) == TYPE_STRING and e["commercial"] == "varies":
			out["perFile"].append(e)
		if e.get("status") == "needs-review":
			out["openQuestions"].append(e)
	return out


## The distinct {…} fields of a credit line, in order.
static func credit_fields(line) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(line) != TYPE_STRING:
		return out
	for m in RegEx.create_from_string("\\{[^{}\\n]+\\}").search_all(line):
		if not out.has(m.get_string()):
			out.append(m.get_string())
	return out


## A CREDITS file in Markdown for what `owed` lists. opts: page_url (Callable
## entry -> String), date, source, made_from; the same as creditsFile's.
static func credits_file(owed: Dictionary, opts: Dictionary = {}) -> String:
	var page_url: Callable = opts.get("page_url", func(_e): return "")
	var date := String(opts.get("date", ""))
	var source := String(opts.get("source", "Free Game Dev Assets"))
	var made_from := String(opts.get("made_from", "a shortlist"))
	var out := PackedStringArray()
	var heading := func(text: String) -> void:
		out.append_array(["", "## " + text, ""])
	var name := func(e: Dictionary) -> String:
		var url := String(page_url.call(e))
		return "[%s](%s)" % [e["name"], url] if url != "" else String(e["name"])
	var list := func(items: Array) -> void:
		for e in items:
			out.append("- %s (%s)" % [name.call(e), e["license"]])

	out.append("# Credits")
	out.append_array(["", "Made from %s on %s%s. Each licence was checked at its source on the date its catalog entry shows. This is the catalog's reading, not legal advice: re-read the source before you ship." % [made_from, source, (" on " + date) if date != "" else ""]])

	if not owed["credits"].is_empty():
		heading.call("Credits to ship")
		var templated := PackedStringArray()
		for e in owed["credits"]:
			if not credit_fields(e.get("credit_line")).is_empty():
				templated.append(String(e["name"]))
		if not templated.is_empty():
			out.append_array(["%s The lines for %s are templates: put in the work you use." % [FILL_IN_HEADER, ", ".join(templated)], ""])
		for e in owed["credits"]:
			var line = e.get("credit_line")
			if typeof(line) == TYPE_STRING and line != "":
				out.append("- " + line)
			else:
				out.append("- %s: no canned credit line; see the entry." % name.call(e))
	if not owed["notices"].is_empty():
		heading.call("Notices to keep with the files")
		out.append_array(["Carry each licence and copyright notice with what you redistribute. This is not a credits-screen line.", ""])
		list.call(owed["notices"])
	if not owed["perFile"].is_empty():
		heading.call("Check each file")
		out.append_array(["Some files in these sources qualify and some do not. Check the licence of each file you take.", ""])
		list.call(owed["perFile"])
	if not owed["openQuestions"].is_empty():
		heading.call("Open questions")
		out.append_array(["These entries are marked needs review: something about their terms is not settled.", ""])
		list.call(owed["openQuestions"])
	if not owed["unclear"].is_empty():
		heading.call("Unclear credit")
		out.append_array(["Whether credit is required is not recorded. Read the entry's Notes.", ""])
		list.call(owed["unclear"])
	if not owed["noCredit"].is_empty():
		heading.call("No credit needed")
		list.call(owed["noCredit"])
	return _collapse_blank_lines("\n".join(out)) + "\n"


static func _collapse_blank_lines(text: String) -> String:
	return RegEx.create_from_string("\\n{3,}").sub(text, "\n\n", true)


# --- The project's list ------------------------------------------------------

## Reads the list file's text. Returns {ids, known, error}; on an error the
## file must not be overwritten, so the user's list is never lost.
static func parse_list(text: String) -> Dictionary:
	var out := {"ids": [], "known": {}, "error": ""}
	if text.strip_edges() == "":
		return out
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		out["error"] = "%s is not valid JSON (line %d): fix or remove it" % [LIST_FILE.get_file(), json.get_error_line()]
		return out
	var data: Dictionary = json.data
	var fmt = data.get("format", LIST_FORMAT)
	if (typeof(fmt) == TYPE_INT or typeof(fmt) == TYPE_FLOAT) and int(fmt) > LIST_FORMAT:
		out["error"] = "%s was written by a newer version of the plugin: update the plugin" % LIST_FILE.get_file()
		return out
	if typeof(data.get("ids")) == TYPE_ARRAY:
		for id in data["ids"]:
			if typeof(id) == TYPE_STRING and id != "" and not out["ids"].has(id):
				out["ids"].append(id)
	if typeof(data.get("known")) == TYPE_DICTIONARY:
		for id in data["known"]:
			var k = data["known"][id]
			if typeof(id) == TYPE_STRING and typeof(k) == TYPE_DICTIONARY:
				out["known"][id] = k
	return out


## The list file's text. Stable for the same input, so re-saving an
## unchanged list leaves the file (and git) untouched.
static func list_text(ids: Array, known: Dictionary) -> String:
	var kept := {}
	for id in ids:
		if known.has(id):
			var snap := {}
			for key in _KNOWN_KEYS:
				snap[key] = known[id].get(key)
			kept[id] = snap
	return JSON.stringify({"format": LIST_FORMAT, "ids": ids, "known": kept}, "\t", false) + "\n"


## Entry ids in pasted text, for importing a list made on the website.
## Reads catalog page links (".../entry/<id>/", which the website shortlist's
## licence-changes.opml and exported CREDITS.md links contain) and bare ids
## separated by spaces, commas or new lines. Returns {ids, unknown}: `ids` are
## in the feed, in the order they first appear; `unknown` are linked ids the
## feed doesn't list. Other words are ignored.
static func ids_from_text(text: String, feed: Dictionary) -> Dictionary:
	var in_feed := {}
	for e in feed.get("entries", []):
		in_feed[e["id"]] = true
	var out := {"ids": [], "unknown": []}
	var re := RegEx.create_from_string("entry/([^/\\s\"'<>]+)/|([A-Za-z0-9][A-Za-z0-9._~-]*)")
	for m in re.search_all(text):
		var linked := m.get_string(1) != ""
		var id := m.get_string(1).uri_decode() if linked else m.get_string(2)
		if in_feed.has(id):
			if not out["ids"].has(id):
				out["ids"].append(id)
		elif linked and not out["unknown"].has(id):
			out["unknown"].append(id)
	return out


static func snapshot(e: Dictionary) -> Dictionary:
	var snap := {}
	for key in _KNOWN_KEYS:
		snap[key] = e.get(key)
	return snap


# --- CREDITS.md ----------------------------------------------------------------

## The project's entries whose licence or credit line in the feed differs from
## the snapshot taken when they were added (or last exported). Ids without a
## snapshot, or no longer in the feed, are left out. Returns an Array of
## {id, name, license: [was, now] or [], credit_line: [was, now] or []}.
static func changes(ids: Array, known: Dictionary, feed: Dictionary) -> Array:
	var by_id := {}
	for e in feed.get("entries", []):
		by_id[e["id"]] = e
	var out: Array = []
	for id in ids:
		if not by_id.has(id) or typeof(known.get(id)) != TYPE_DICTIONARY:
			continue
		var was: Dictionary = known[id]
		var now: Dictionary = by_id[id]
		var c := {"id": id, "name": String(now["name"]), "license": [], "credit_line": []}
		for key in ["license", "credit_line"]:
			if was.get(key) != now.get(key):
				c[key] = [was.get(key), now.get(key)]
		if not c["license"].is_empty() or not c["credit_line"].is_empty():
			out.append(c)
	return out


## One change as a short phrase: "Name (licence CC-BY-3.0 → CC-BY-4.0, new credit line)".
static func change_text(c: Dictionary) -> String:
	var what := PackedStringArray()
	if not c["license"].is_empty():
		what.append("licence %s → %s" % [or_none(c["license"][0]), or_none(c["license"][1])])
	if not c["credit_line"].is_empty():
		what.append("new credit line" if c["credit_line"][1] != null else "credit line removed")
	return "%s (%s)" % [c["name"], ", ".join(what)]


static func or_none(v) -> String:
	return String(v) if typeof(v) == TYPE_STRING and v != "" else "none"


## Links each entry to its catalog page, by the same rule as the dock's
## Catalog page button: the feed's `page`, or no link when it looks unsafe.
static func page_url(feed: Dictionary) -> Callable:
	return func(e: Dictionary) -> String:
		return Details.catalog_page_url(feed, e)


## The marked block for the project's list. Returns {text, known, missing, changed}:
## `known` is the refreshed snapshot to save back to the list file,
## `missing` counts ids the feed no longer lists, and `changed` is what
## changes() found against the old snapshot (the block itself matches the
## website export, so the dock reports these).
static func export_block(ids: Array, known: Dictionary, feed: Dictionary) -> Dictionary:
	var changed := changes(ids, known, feed)
	var by_id := {}
	for e in feed.get("entries", []):
		by_id[e["id"]] = e
	var listed: Array = []
	var gone: Array = []
	var new_known := {}
	for id in ids:
		if by_id.has(id):
			listed.append(by_id[id])
			new_known[id] = snapshot(by_id[id])
		else:
			gone.append(id)
			if known.has(id):
				new_known[id] = known[id]

	var body := credits_file(owes(listed), {
		"page_url": page_url(feed),
		"source": "Free Game Dev Assets",
		"made_from": "this project's asset list",
	})
	var out := PackedStringArray([START, body.trim_suffix("\n")])
	if not gone.is_empty():
		out.append_array(["", "## No longer listed", "",
			"The catalog no longer lists these, so their licence may have changed or been withdrawn: check the licence at the source before you ship. The details are from when the plugin last saw them.", ""])
		for id in gone:
			if new_known.has(id):
				var k: Dictionary = new_known[id]
				var line = k.get("credit_line")
				var credit: String = ("credit line: " + line) if typeof(line) == TYPE_STRING and line != "" else "no credit line recorded"
				out.append("- %s (%s), `%s`: %s" % [k.get("name", id), k.get("license", "licence unknown"), id, credit])
			else:
				out.append("- `%s`: no details were saved; check the licence." % id)
	out.append_array(["", "<sub>Written by the Free Game Dev Assets Godot plugin from catalog %s. The plugin replaces everything between these markers when you export again; write your own text outside them.</sub>" % feed.get("version", "?"), END])
	return {"text": "\n".join(out) + "\n", "known": new_known, "missing": gone.size(), "changed": changed}


## Puts `block` into an existing CREDITS file in place of the old block, or
## appends it. Returns {ok, text, error}. Refuses a file whose markers are
## broken rather than guess what to replace.
static func merge(existing: String, block: String) -> Dictionary:
	var crlf := existing.contains("\r\n")
	var text := existing.replace("\r\n", "\n")
	var starts := text.count(START)
	var ends := text.count(END)
	var out := {"ok": true, "text": "", "error": ""}
	if starts == 0 and ends == 0:
		if text.strip_edges() == "":
			text = block
		else:
			text = text.trim_suffix("\n") + "\n\n" + block
	elif starts == 1 and ends == 1 and text.find(START) < text.find(END):
		var a := text.find(START)
		var b := text.find(END) + END.length()
		if b < text.length() and text[b] == "\n":
			b += 1
		text = text.substr(0, a) + block + text.substr(b)
	else:
		out["ok"] = false
		out["error"] = "%s has %d start and %d end markers: fix them so there is one of each, start first" % [CREDITS_FILE.get_file(), starts, ends]
		return out
	out["text"] = text.replace("\n", "\r\n") if crlf else text
	return out
