extends SceneTree
## Headless unit tests. Run from the repo root:
##   godot --headless --path . --script tests/run_tests.gd
## Exits 0 when every check passes, 1 otherwise.

const Feed := preload("res://addons/free_game_dev_assets/feed.gd")
const Cache := preload("res://addons/free_game_dev_assets/feed_cache.gd")
const FeedClient := preload("res://addons/free_game_dev_assets/feed_client.gd")
const Browse := preload("res://addons/free_game_dev_assets/browse.gd")
const Details := preload("res://addons/free_game_dev_assets/entry_details.gd")

const FIXTURE := "res://tests/fixtures/feed_v1.json"
const SCRATCH := "user://test_cache"

var _passed := 0
var _failed: Array[String] = []


func _initialize() -> void:
	_clear_scratch()
	_test_parse()
	_test_cache()
	_test_client()
	_test_browse()
	_test_details()
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

func _test_parse() -> void:
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


# --- feed_cache.gd -----------------------------------------------------------

func _test_cache() -> void:
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


# --- feed_client.gd ----------------------------------------------------------
# Calls the response handler directly with fake responses: no network.

func _client() -> Array:
	var client = FeedClient.new()
	client.cache_dir = ProjectSettings.globalize_path(SCRATCH)
	var got: Array = []
	client.loaded.connect(func(state): got.append(state))
	return [client, got]


func _test_client() -> void:
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


func _test_browse() -> void:
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
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("filters", "commercial", "yes")
	cfg.set_value("filters", "category", 7)
	cfg.save(path)
	var loaded := Browse.load_filters(path)
	eq("filters: wrong type falls back (bool)", loaded["commercial"], false)
	eq("filters: wrong type falls back (string)", loaded["category"], "")
	DirAccess.remove_absolute(path)


# --- entry_details.gd --------------------------------------------------------

func _test_details() -> void:
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


func _clear_scratch() -> void:
	var dir := ProjectSettings.globalize_path(SCRATCH)
	for name in [Cache.FEED_FILE, Cache.META_FILE, Cache.FEED_FILE + ".tmp"]:
		if FileAccess.file_exists(dir.path_join(name)):
			DirAccess.remove_absolute(dir.path_join(name))
