extends SceneTree
## Headless unit tests. Run from the repo root:
##   godot --headless --path . --script tests/run_tests.gd
## Exits 0 when every check passes, 1 otherwise.

const Feed := preload("res://addons/free_game_dev_assets/feed.gd")
const Cache := preload("res://addons/free_game_dev_assets/feed_cache.gd")
const FeedClient := preload("res://addons/free_game_dev_assets/feed_client.gd")
const Browse := preload("res://addons/free_game_dev_assets/browse.gd")
const Details := preload("res://addons/free_game_dev_assets/entry_details.gd")
const Credits := preload("res://addons/free_game_dev_assets/credits.gd")

const FIXTURE := "res://tests/fixtures/feed_v1.json"
const SCRATCH := "user://test_cache"

var _passed := 0
var _failed: Array[String] = []


## A feed client whose request is recorded instead of sent.
class FakeClient extends "res://addons/free_game_dev_assets/feed_client.gd":
	var sent: Array = []  # the headers of each request started
	var send_error := OK

	func _send(_request_url: String, headers: PackedStringArray) -> int:
		sent.append(headers)
		return send_error


## Runs one group of checks. Each group ends with `return true`, so a script
## error part-way through (which returns null) fails the run instead of
## skipping the rest of the group's checks silently.
func _run(group: String) -> void:
	if call(group) != true:
		_failed.append("%s: stopped part-way, see the SCRIPT ERROR above" % group)


func _initialize() -> void:
	_clear_scratch()
	_run("_test_parse")
	_run("_test_cache")
	_run("_test_client")
	_run("_test_client_request")
	_run("_test_browse")
	_run("_test_details")
	_run("_test_credits")
	_clear_scratch()
	if _failed.is_empty():
		print("tests ok: %d checks" % _passed)
		quit(0)
	else:
		printerr("tests failed (%d of %d):" % [_failed.size(), _failed.size() + _passed])
		for f in _failed:
			printerr("  - " + f)
		quit(1)


func eq(label: String, actual, expected) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		_passed += 1
	else:
		_failed.append("%s: expected %s, got %s" % [label, var_to_str(expected), var_to_str(actual)])


func fixture_text() -> String:
	return FileAccess.get_file_as_string(FIXTURE)


func fixture_with(changes: Dictionary) -> String:
	var data: Dictionary = JSON.parse_string(fixture_text())
	data.merge(changes, true)
	return JSON.stringify(data)


# --- feed.gd -----------------------------------------------------------------

func _test_parse() -> bool:
	var r := Feed.parse(fixture_text())
	eq("parse: fixture is ok", r["ok"], true)
	eq("parse: fixture keeps every entry", r["feed"]["entries"].size(), 4)
	eq("parse: nothing dropped", r["dropped"], 0)
	eq("parse: version", r["feed"]["version"].begins_with("v"), true)

	eq("parse: not JSON", Feed.parse("<html>")["ok"], false)
	eq("parse: JSON array is not a feed", Feed.parse("[]")["ok"], false)
	eq("parse: no format", Feed.parse('{"version":"v1","entries":[]}')["ok"], false)

	var newer := Feed.parse(fixture_with({"format": Feed.SUPPORTED_FORMAT + 1}))
	eq("parse: newer format is refused", newer["ok"], false)
	eq("parse: newer format is flagged", newer["too_new"], true)
	eq("parse: newer format says update", newer["error"].contains("update the plugin"), true)

	var data: Dictionary = JSON.parse_string(fixture_text())
	data["entries"].append({"id": "broken"})
	data["entries"].append("not an entry")
	var dropped := Feed.parse(JSON.stringify(data))
	eq("parse: malformed entries are dropped", dropped["dropped"], 2)
	eq("parse: good entries are kept", dropped["feed"]["entries"].size(), 4)

	var unknown := Feed.parse(fixture_with({"somethingNew": {"a": 1}}))
	eq("parse: unknown keys are ignored", unknown["ok"], true)

	var bad_site := Feed.parse(fixture_with({"siteUrl": "javascript:alert(1)"}))
	eq("parse: non-https siteUrl falls back", bad_site["feed"]["siteUrl"], Feed.DEFAULT_SITE_URL)

	var no_maps := Feed.parse(fixture_with({"categories": null}))
	eq("parse: missing categories becomes {}", no_maps["feed"]["categories"], {})
	return true


# --- feed_cache.gd -----------------------------------------------------------

func _test_cache() -> bool:
	var dir := ProjectSettings.globalize_path(SCRATCH)
	eq("cache: empty dir has no text", Cache.read_text(dir), "")
	eq("cache: empty dir has no meta", Cache.read_meta(dir), {})
	eq("cache: write", Cache.write(dir, "hello", {"etag": "\"abc\"", "fetched_at": 100.0}), true)
	eq("cache: read back", Cache.read_text(dir), "hello")
	eq("cache: meta etag", Cache.read_meta(dir).get("etag"), "\"abc\"")
	eq("cache: overwrite", Cache.write(dir, "again", {"fetched_at": 200.0}), true)
	eq("cache: read overwritten", Cache.read_text(dir), "again")
	eq("cache: no tmp file left", FileAccess.file_exists(dir.path_join(Cache.FEED_FILE + ".tmp")), false)

	eq("fresh: just fetched", Cache.is_fresh({"fetched_at": 1000.0}, 1000.0 + 60), true)
	eq("fresh: a day old is stale", Cache.is_fresh({"fetched_at": 1000.0}, 1000.0 + Cache.MAX_AGE_SEC), false)
	eq("fresh: clock went backwards is stale", Cache.is_fresh({"fetched_at": 1000.0}, 900.0), false)
	eq("fresh: no meta is stale", Cache.is_fresh({}, 1000.0), false)
	_clear_scratch()
	return true


# --- feed_client.gd ----------------------------------------------------------
# Calls the response handler directly with fake responses: no network.

func _client() -> Array:
	var client = FeedClient.new()
	client.cache_dir = ProjectSettings.globalize_path(SCRATCH)
	var got: Array = []
	client.loaded.connect(func(state): got.append(state))
	return [client, got]


func _test_client() -> bool:
	var body := fixture_text().to_utf8_buffer()
	var ok := HTTPRequest.RESULT_SUCCESS
	var dir := ProjectSettings.globalize_path(SCRATCH)

	# No cache, offline: nothing to show, a message.
	var c := _client()
	c[0]._on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	eq("client offline, no cache: source", c[1][0]["source"], "none")
	eq("client offline, no cache: empty feed", c[1][0]["feed"].is_empty(), true)
	eq("client offline, no cache: says why", c[1][0]["message"].contains("no connection"), true)
	c[0].free()

	# 200: parsed, cached with validators.
	c = _client()
	c[0]._on_request_completed(ok, 200, PackedStringArray(["ETag: \"v1\"", "Last-Modified: Mon, 09 Nov 2026 00:00:00 GMT"]), body)
	eq("client 200: source", c[1][0]["source"], "network")
	eq("client 200: entries", c[1][0]["feed"]["entries"].size(), 4)
	eq("client 200: cached", Cache.read_text(dir) != "", true)
	eq("client 200: etag kept", Cache.read_meta(dir).get("etag"), "\"v1\"")
	eq("client 200: last-modified kept", Cache.read_meta(dir).get("last_modified"), "Mon, 09 Nov 2026 00:00:00 GMT")
	c[0].free()

	# 304 with a cache: cached copy, marked fresh.
	Cache.write_meta(dir, {"etag": "\"v1\"", "fetched_at": 0.0})
	c = _client()
	c[0]._on_request_completed(ok, 304, PackedStringArray(), PackedByteArray())
	eq("client 304: source", c[1][0]["source"], "cache")
	eq("client 304: no message", c[1][0]["message"], "")
	eq("client 304: marked fresh", Cache.is_fresh(Cache.read_meta(dir), Time.get_unix_time_from_system()), true)
	c[0].free()

	# Fresh cache: refresh() answers from it without a request.
	c = _client()
	c[0].refresh()
	eq("client fresh cache: answered at once", c[1].size(), 1)
	eq("client fresh cache: source", c[1][0]["source"], "cache")
	eq("client fresh cache: no request in flight", c[0].is_busy(), false)
	c[0].free()

	# Offline with a cache: cached copy and the reason.
	c = _client()
	c[0]._on_request_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	eq("client offline with cache: source", c[1][0]["source"], "cache")
	eq("client offline with cache: says so", c[1][0]["message"].contains("timed out"), true)
	c[0].free()

	# A newer feed format: keep the cache, say update.
	c = _client()
	c[0]._on_request_completed(ok, 200, PackedStringArray(), fixture_with({"format": Feed.SUPPORTED_FORMAT + 1}).to_utf8_buffer())
	eq("client newer format: keeps cache", c[1][0]["source"], "cache")
	eq("client newer format: says update", c[1][0]["message"].contains("update the plugin"), true)
	eq("client newer format: cache not overwritten", Feed.parse(Cache.read_text(dir))["ok"], true)
	c[0].free()

	# A server error page: keep the cache.
	c = _client()
	c[0]._on_request_completed(ok, 503, PackedStringArray(), "<html>busy</html>".to_utf8_buffer())
	eq("client 503: keeps cache", c[1][0]["source"], "cache")
	eq("client 503: says code", c[1][0]["message"].contains("503"), true)
	c[0].free()

	# A newer format with no cache: nothing to show, say update.
	_clear_scratch()
	c = _client()
	c[0]._on_request_completed(ok, 200, PackedStringArray(), fixture_with({"format": Feed.SUPPORTED_FORMAT + 1}).to_utf8_buffer())
	eq("client newer format, no cache: source", c[1][0]["source"], "none")
	eq("client newer format, no cache: says update", c[1][0]["message"].contains("update the plugin"), true)
	c[0].free()
	return true


## refresh(): when it asks the network, and with which headers. FakeClient
## records the request instead of sending it.
func _fake_client() -> Array:
	var client := FakeClient.new()
	client.cache_dir = ProjectSettings.globalize_path(SCRATCH)
	var got: Array = []
	client.loaded.connect(func(state): got.append(state))
	return [client, got]


func _test_client_request() -> bool:
	var dir := ProjectSettings.globalize_path(SCRATCH)
	var ua := "User-Agent: " + FeedClient.USER_AGENT
	var stale := {"etag": "\"v1\"", "last_modified": "Mon, 09 Nov 2026 00:00:00 GMT", "fetched_at": 0.0}

	eq("headers: no cache, only the User-Agent", FeedClient.request_headers(false, stale), PackedStringArray([ua]))
	eq("headers: cache with validators", FeedClient.request_headers(true, stale), PackedStringArray([
		ua, "If-None-Match: \"v1\"", "If-Modified-Since: Mon, 09 Nov 2026 00:00:00 GMT"]))
	eq("headers: cache without validators", FeedClient.request_headers(true, {}), PackedStringArray([ua]))

	# A stale cache: one request, with its validators; busy until it answers.
	_clear_scratch()
	Cache.write(dir, fixture_text(), stale)
	var c := _fake_client()
	c[0].refresh()
	eq("stale cache: one request", c[0].sent.size(), 1)
	eq("stale cache: sends the validators", c[0].sent[0], FeedClient.request_headers(true, stale))
	eq("stale cache: nothing reported yet", c[1].size(), 0)
	eq("stale cache: busy", c[0].is_busy(), true)
	c[0].refresh()
	eq("busy: a second refresh sends nothing", c[0].sent.size(), 1)
	eq("busy: and reports nothing", c[1].size(), 0)
	c[0]._on_request_completed(HTTPRequest.RESULT_SUCCESS, 304, PackedStringArray(), PackedByteArray())
	eq("answered: no longer busy", c[0].is_busy(), false)
	eq("answered: reported once", c[1].size(), 1)
	c[0].free()

	# Meta left behind without a body: no validators, or the server could
	# answer 304 with nothing to show.
	_clear_scratch()
	Cache.write_meta(dir, stale)
	c = _fake_client()
	c[0].refresh()
	eq("meta without a body: only the User-Agent", c[0].sent[0], PackedStringArray([ua]))
	# Should a 304 come anyway, there is nothing to show: say so.
	c[0]._on_request_completed(HTTPRequest.RESULT_SUCCESS, 304, PackedStringArray(), PackedByteArray())
	eq("304 without a cache: source", c[1][0]["source"], "none")
	eq("304 without a cache: says why", c[1][0]["message"].contains("304"), true)
	c[0].free()

	# A fresh cache: no request, unless forced (the Refresh button).
	_clear_scratch()
	Cache.write(dir, fixture_text(), {"etag": "\"v1\"", "fetched_at": Time.get_unix_time_from_system()})
	c = _fake_client()
	c[0].refresh()
	eq("fresh cache: no request", c[0].sent.size(), 0)
	c[0].refresh(true)
	eq("fresh cache, forced: one request", c[0].sent.size(), 1)
	eq("fresh cache, forced: sends the validators", c[0].sent[0].has("If-None-Match: \"v1\""), true)
	c[0].free()

	# The request can't start: not left busy, the cache is shown with the reason.
	c = _fake_client()
	c[0].send_error = ERR_CANT_CONNECT
	c[0].refresh(true)
	eq("can't start: not busy", c[0].is_busy(), false)
	eq("can't start: shows the cache", c[1][0]["source"], "cache")
	eq("can't start: says why", c[1][0]["message"].contains("could not start"), true)
	c[0].free()
	_clear_scratch()
	return true


# --- browse.gd ---------------------------------------------------------------

func _ids(entries: Array) -> Array:
	return entries.map(func(e): return e["id"])


func _browse_entries() -> Array:
	var entries: Array = Feed.parse(fixture_text())["feed"]["entries"]
	# A non-commercial, needs-review entry the fixture lacks.
	var nc: Dictionary = entries[2].duplicate(true)
	nc.merge({"id": "nc-pack", "name": "Zeta NC Pack", "category": "audio", "license": "CC-BY-NC-4.0",
		"licenseFamily": "custom", "commercial": false, "attribution_required": true,
		"works_in": ["godot"], "made_for": [], "status": "needs-review",
		"publisher": "Kenney Fan", "summary": "Non-commercial sounds", "tags": ["sfx"]}, true)
	entries.append(nc)
	return entries


func _test_browse() -> bool:
	var all := _browse_entries()
	var none := Browse.default_filters()
	none["godot"] = false

	eq("browse: defaults have Works in Godot on", Browse.default_filters()["godot"], true)
	eq("browse: no filters keeps all", Browse.apply(all, none).size(), 5)
	eq("browse: Works in Godot drops the Unreal-only entry",
		_ids(Browse.apply(all, Browse.default_filters())).has("als-community"), false)
	eq("browse: Works in Godot keeps the rest", Browse.apply(all, Browse.default_filters()).size(), 4)

	eq("browse: sort puts made-for-Godot first, then by name", _ids(Browse.apply(all, none)),
		["beehave", "ox72-dungeon-tileset", "accad-mocap", "als-community", "nc-pack"])

	var f := none.duplicate()
	f["category"] = "tools"
	eq("browse: category", _ids(Browse.apply(all, f)), ["beehave", "als-community"])

	f = none.duplicate()
	f["license_family"] = "permissive"
	eq("browse: licence family", _ids(Browse.apply(all, f)), ["beehave", "als-community"])

	f = none.duplicate()
	f["commercial"] = true
	eq("browse: commercial use OK", _ids(Browse.apply(all, f)).has("nc-pack"), false)
	eq("browse: commercial keeps the others", Browse.apply(all, f).size(), 4)

	f = none.duplicate()
	f["no_credit"] = true
	eq("browse: no credit needed", _ids(Browse.apply(all, f)),
		["beehave", "ox72-dungeon-tileset", "als-community"])

	f = none.duplicate()
	f["query"] = "DUNGEON"
	eq("browse: search name, case-insensitive", _ids(Browse.apply(all, f)), ["ox72-dungeon-tileset"])
	f["query"] = "behavior-tree"
	eq("browse: search tags", _ids(Browse.apply(all, f)), ["beehave"])
	f["query"] = "kenney fan"
	eq("browse: search publisher", _ids(Browse.apply(all, f)), ["nc-pack"])
	f["query"] = "non-commercial sounds"
	eq("browse: search summary", _ids(Browse.apply(all, f)), ["nc-pack"])
	f["query"] = "  locomotion   walking "
	eq("browse: every word must match", _ids(Browse.apply(all, f)), ["accad-mocap"])
	f["query"] = "nothing-matches-this"
	eq("browse: no match", Browse.apply(all, f).size(), 0)

	f = none.duplicate()
	f["category"] = "tools"
	f["no_credit"] = true
	f["godot"] = true
	eq("browse: filters combine", _ids(Browse.apply(all, f)), ["beehave"])

	var odd: Dictionary = all[0].duplicate(true)
	odd.erase("commercial")
	odd.erase("summary")
	odd["publisher"] = null
	f = none.duplicate()
	f["commercial"] = true
	f["query"] = "dungeon"
	eq("browse: missing fields don't pass a filter or crash", Browse.apply([odd], f).size(), 0)

	# Saved state.
	var path := ProjectSettings.globalize_path(SCRATCH).path_join(Browse.SETTINGS_FILE)
	eq("filters: nothing saved gives defaults", Browse.load_filters(path), Browse.default_filters())
	var saved := Browse.default_filters()
	saved.merge({"query": "tiles", "category": "2d", "license_family": "cc-by",
		"commercial": true, "no_credit": true, "godot": false}, true)
	eq("filters: save", Browse.save_filters(path, saved), true)
	eq("filters: round trip", Browse.load_filters(path), saved)
	# "Only this project's" belongs to one project; the file is editor-wide.
	var project_only := saved.duplicate()
	project_only["project_only"] = true
	Browse.save_filters(path, project_only)
	eq("filters: project_only is not saved", Browse.load_filters(path)["project_only"], false)
	var old := ConfigFile.new()
	old.load(path)
	old.set_value("filters", "project_only", true)  # as 0.1.0 saved it
	old.save(path)
	eq("filters: a project_only saved by 0.1.0 is ignored", Browse.load_filters(path)["project_only"], false)
	Browse.save_filters(path, saved)
	var resaved := ConfigFile.new()
	resaved.load(path)
	eq("filters: saving drops an old project_only", resaved.has_section_key("filters", "project_only"), false)
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("filters", "commercial", "yes")
	cfg.set_value("filters", "category", 7)
	cfg.save(path)
	var loaded := Browse.load_filters(path)
	eq("filters: wrong type falls back (bool)", loaded["commercial"], false)
	eq("filters: wrong type falls back (string)", loaded["category"], "")
	DirAccess.remove_absolute(path)
	return true


# --- entry_details.gd --------------------------------------------------------

func _test_details() -> bool:
	var feed: Dictionary = Feed.parse(fixture_text())["feed"]
	var tileset: Dictionary = feed["entries"][0]   # CC0, no credit
	var mocap: Dictionary = feed["entries"][2]     # CC-BY-3.0, credit line

	eq("https: plain", Details.is_https("https://example.com/x"), true)
	eq("https: http refused", Details.is_https("http://mocap.cs.cmu.edu"), false)
	eq("https: javascript refused", Details.is_https("javascript:alert(1)"), false)
	eq("https: file refused", Details.is_https("file:///C:/Windows"), false)
	eq("https: no host refused", Details.is_https("https://"), false)
	eq("https: path-only host refused", Details.is_https("https:///etc/passwd"), false)
	eq("https: whitespace refused", Details.is_https("https://example.com/a b"), false)
	eq("https: newline refused", Details.is_https("https://example.com/\nfile:///x"), false)
	eq("https: upper-case scheme refused", Details.is_https("HTTPS://example.com"), false)
	eq("https: not a string", Details.is_https(null), false)

	eq("source url: https kept", Details.source_url(tileset), tileset["url"])
	var http_entry := tileset.duplicate()
	http_entry["url"] = "http://www.makehumancommunity.org"
	eq("source url: http refused", Details.source_url(http_entry), "")

	eq("catalog page: joined to siteUrl", Details.catalog_page_url(feed, tileset),
		"https://tmhsdigital.github.io/Free-Game-Dev-Assets/entry/ox72-dungeon-tileset/")
	var no_slash := feed.duplicate()
	no_slash["siteUrl"] = "https://tmhsdigital.github.io/Free-Game-Dev-Assets"
	eq("catalog page: siteUrl without a trailing slash", Details.catalog_page_url(no_slash, tileset),
		"https://tmhsdigital.github.io/Free-Game-Dev-Assets/entry/ox72-dungeon-tileset/")
	for bad in ["https://evil.example/", "//evil.example/x", "../../x", "entry/a b/", "javascript:alert(1)", ""]:
		var e := tileset.duplicate()
		e["page"] = bad
		eq("catalog page: refuses %s" % bad, Details.catalog_page_url(feed, e), "")

	eq("commercial: true", Details.commercial_text(true), "Yes")
	eq("commercial: false", Details.commercial_text(false), "No")
	eq("commercial: varies", Details.commercial_text("varies"), "Varies by file")
	eq("commercial: unknown", Details.commercial_text("unknown").begins_with("Unknown"), true)
	eq("commercial: missing", Details.commercial_text(null).begins_with("Unknown"), true)

	var c := Details.credit(tileset)
	eq("credit, none needed: can't copy", c["can_copy"], false)
	eq("credit, none needed: says so", c["text"], "Not required")
	eq("credit, none needed: button note", c["note"], "No credit is required for this entry.")

	c = Details.credit(mocap)
	eq("credit, required: can copy", c["can_copy"], true)
	eq("credit, required: line is the feed's, unchanged", c["line"], mocap["credit_line"])
	eq("credit, required: says so", c["text"], "Required")

	var notice := mocap.duplicate()
	notice["attributionClass"] = "notice"
	eq("credit, notice: keep the licence text", Details.credit(notice)["text"].contains("licence text"), true)

	var unknown := tileset.duplicate()
	unknown["attribution_required"] = "unknown"
	c = Details.credit(unknown)
	eq("credit, unknown: can't copy", c["can_copy"], false)
	eq("credit, unknown: says unknown", c["text"].begins_with("Unknown"), true)

	var missing_line := mocap.duplicate()
	missing_line["credit_line"] = null
	c = Details.credit(missing_line)
	eq("credit, required but no line: can't copy", c["can_copy"], false)
	eq("credit, required but no line: points to the catalog page", c["note"].contains("catalog page"), true)

	var blanks := mocap.duplicate()
	blanks["credit_line"] = "\"{title}\" by Someone (CC BY 4.0)"
	eq("credit, {…} fields: fill-in note", Details.credit(blanks)["fill_in"], true)
	eq("credit, plain line: no fill-in note", Details.credit(mocap)["fill_in"], false)

	eq("licence text: with SPDX id", Details.licence_text({"license": "CC-BY-3.0", "license_spdx": "CC-BY-3.0"}), "CC-BY-3.0")
	eq("licence text: SPDX differs", Details.licence_text({"license": "SIL OFL", "license_spdx": "OFL-1.1"}), "SIL OFL (OFL-1.1)")
	eq("licence text: no SPDX", Details.licence_text({"license": "custom", "license_spdx": null}), "custom")

	eq("verified note: dated", Details.verified_note(tileset),
		"Licence as recorded on %s. Check the source before you ship." % tileset["verified"])
	eq("verified note: no date", Details.verified_note({"verified": null}),
		"Licence as recorded by the catalog. Check the source before you ship.")
	return true


# --- credits.gd --------------------------------------------------------------

func _credit_entries() -> Array:
	var base: Dictionary = Feed.parse(fixture_text())["feed"]["entries"][2]  # CC-BY, credit line
	var make := func(id: String, changes: Dictionary) -> Dictionary:
		var e: Dictionary = base.duplicate(true)
		e.merge({"id": id, "name": id.replace("-", " ").capitalize(), "page": "entry/%s/" % id}, true)
		e.merge(changes, true)
		return e
	return [
		make.call("credit-a", {"credit_line": "Art by A (CC BY 4.0)"}),
		make.call("template-b", {"credit_line": "\"{title}\" by B (CC BY 4.0)"}),
		make.call("no-line-c", {"credit_line": null}),
		make.call("mit-d", {"license": "MIT", "attribution_required": false, "attributionClass": "notice", "credit_line": null}),
		make.call("cc0-e", {"license": "CC0", "attribution_required": false, "attributionClass": "none", "credit_line": null}),
		make.call("unknown-f", {"license": "custom", "attribution_required": "unknown", "attributionClass": "any", "credit_line": null}),
		make.call("varies-g", {"license": "mixed", "commercial": "varies", "attribution_required": false, "attributionClass": "none", "credit_line": null}),
		make.call("review-h", {"license": "CC0", "status": "needs-review", "attribution_required": false, "attributionClass": "none", "credit_line": null}),
	]


func _test_credits() -> bool:
	var entries := _credit_entries()
	var owed := Credits.owes(entries)
	eq("owes: credits", _ids(owed["credits"]), ["credit-a", "template-b", "no-line-c"])
	eq("owes: notices", _ids(owed["notices"]), ["mit-d"])
	eq("owes: no credit leaves out notices", _ids(owed["noCredit"]), ["cc0-e", "varies-g", "review-h"])
	eq("owes: unclear", _ids(owed["unclear"]), ["unknown-f"])
	eq("owes: per file", _ids(owed["perFile"]), ["varies-g"])
	eq("owes: open questions", _ids(owed["openQuestions"]), ["review-h"])
	eq("owes: duplicate ids listed once", Credits.owes([entries[0], entries[0]])["credits"].size(), 1)

	var page := func(e): return "https://example.org/entry/%s/" % e["id"]
	var text := Credits.credits_file(owed, {"page_url": page, "date": "2026-11-10", "source": "Free Game Dev Assets", "made_from": "a shortlist"})
	var lines := text.split("\n")
	eq("file: title", lines[0], "# Credits")
	eq("file: intro", lines[2], "Made from a shortlist on Free Game Dev Assets on 2026-11-10. Each licence was checked at its source on the date its catalog entry shows. This is the catalog's reading, not legal advice: re-read the source before you ship.")
	eq("file: credit line verbatim", lines.has("- Art by A (CC BY 4.0)"), true)
	eq("file: template header", text.contains("Fill in every {…} field below before you ship. The lines for Template B are templates: put in the work you use."), true)
	eq("file: no canned line", lines.has("- [No Line C](https://example.org/entry/no-line-c/): no canned credit line; see the entry."), true)
	eq("file: notice listed", lines.has("- [Mit D](https://example.org/entry/mit-d/) (MIT)"), true)
	eq("file: sections in the site's order", _order(text, ["## Credits to ship", "## Notices to keep with the files", "## Check each file", "## Open questions", "## Unclear credit", "## No credit needed"]), true)
	eq("file: no triple newlines", text.contains("\n\n\n"), false)
	eq("file: ends with one newline", text.ends_with("\n") and not text.ends_with("\n\n"), true)
	eq("file: empty sections left out", Credits.credits_file(Credits.owes([entries[4]]), {}).contains("## Credits to ship"), false)

	# Project list file.
	eq("list: empty text is an empty list", Credits.parse_list("")["ids"], [])
	var parsed := Credits.parse_list('{"format":1,"ids":["a","b",3,"a"],"known":{"a":{"name":"A","license":"MIT","credit_line":null}}}')
	eq("list: ids kept in order, bad and duplicate dropped", parsed["ids"], ["a", "b"])
	eq("list: known kept", parsed["known"]["a"]["name"], "A")
	eq("list: not JSON is an error", Credits.parse_list("{oops")["error"] != "", true)
	eq("list: newer format is an error", Credits.parse_list('{"format":2,"ids":[]}')["error"].contains("newer"), true)
	var round := Credits.parse_list(Credits.list_text(["x", "y"], {"x": {"name": "X", "license": "CC0", "credit_line": null}}))
	eq("list: round trip ids", round["ids"], ["x", "y"])
	eq("list: round trip known", round["known"]["x"]["license"], "CC0")
	eq("list: text is stable", Credits.list_text(["x"], {}), Credits.list_text(["x"], {}))

	# The block between the markers.
	var block := Credits.START + "\nnew\n" + Credits.END + "\n"
	eq("merge: new file is the block", Credits.merge("", block)["text"], block)
	var mine := "My own credits\n\n" + Credits.START + "\nold\n" + Credits.END + "\n\nThanks to my friends.\n"
	var merged := Credits.merge(mine, block)
	eq("merge: replaces only the block", merged["text"], "My own credits\n\n" + Credits.START + "\nnew\n" + Credits.END + "\n\nThanks to my friends.\n")
	eq("merge: twice changes nothing", Credits.merge(merged["text"], block)["text"], merged["text"])
	eq("merge: file without markers gets the block appended", Credits.merge("Hand-written\n", block)["text"], "Hand-written\n\n" + block)
	eq("merge: start without end is refused", Credits.merge(Credits.START + "\nhalf", block)["ok"], false)
	eq("merge: two blocks are refused", Credits.merge(block + block, block)["ok"], false)
	eq("merge: CRLF file keeps CRLF", Credits.merge("Mine\r\n" + Credits.START + "\r\nold\r\n" + Credits.END + "\r\n", block)["text"],
		"Mine\r\n" + Credits.START + "\r\nnew\r\n" + Credits.END + "\r\n")

	# The whole export.
	var feed: Dictionary = {"version": "v2026.11.10", "siteUrl": "https://example.org/", "entries": entries}
	var known := {"gone-z": {"name": "Gone Z", "license": "CC-BY-4.0", "credit_line": "Sound by Z (CC BY 4.0)"}}
	var out := Credits.export_block(["credit-a", "no-line-c", "gone-z", "never-known"], known, feed)
	eq("export: has markers", out["text"].begins_with(Credits.START) and out["text"].strip_edges().ends_with(Credits.END), true)
	eq("export: listed entry credited", out["text"].contains("- Art by A (CC BY 4.0)"), true)
	eq("export: page links use the feed siteUrl", out["text"].contains("https://example.org/entry/"), true)
	eq("export: removed id flagged", out["text"].contains("## No longer listed"), true)
	eq("export: removed id keeps its credit line", out["text"].contains("Sound by Z (CC BY 4.0)"), true)
	eq("export: removed id says check the licence", out["text"].contains("check the licence"), true)
	eq("export: unknown id flagged by id", out["text"].contains("`never-known`"), true)
	eq("export: counts missing", out["missing"], 2)
	eq("export: snapshot refreshed for listed ids", out["known"]["credit-a"]["credit_line"], "Art by A (CC BY 4.0)")
	eq("export: snapshot kept for removed ids", out["known"]["gone-z"]["name"], "Gone Z")
	eq("export: feed version named", out["text"].contains("v2026.11.10"), true)
	eq("export: same input, same output", Credits.export_block(["credit-a", "no-line-c", "gone-z", "never-known"], known, feed)["text"], out["text"])
	return true


func _order(text: String, parts: Array) -> bool:
	var at := -1
	for p in parts:
		var i := text.find(p)
		if i <= at:
			return false
		at = i
	return true


func _clear_scratch() -> void:
	var dir := ProjectSettings.globalize_path(SCRATCH)
	for name in [Cache.FEED_FILE, Cache.META_FILE, Cache.FEED_FILE + ".tmp"]:
		if FileAccess.file_exists(dir.path_join(name)):
			DirAccess.remove_absolute(dir.path_join(name))
