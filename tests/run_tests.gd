extends SceneTree
## Headless unit tests. Run from the repo root:
##   godot --headless --path . --script tests/run_tests.gd
## Exits 0 when every check passes, 1 otherwise.

const Feed := preload("res://addons/free_game_dev_assets/feed.gd")
const Cache := preload("res://addons/free_game_dev_assets/feed_cache.gd")
const FeedClient := preload("res://addons/free_game_dev_assets/feed_client.gd")

const FIXTURE := "res://tests/fixtures/feed_v1.json"
const SCRATCH := "user://test_cache"

var _passed := 0
var _failed: Array[String] = []


func _initialize() -> void:
	_clear_scratch()
	_test_parse()
	_test_cache()
	_test_client()
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


func _clear_scratch() -> void:
	var dir := ProjectSettings.globalize_path(SCRATCH)
	for name in [Cache.FEED_FILE, Cache.META_FILE, Cache.FEED_FILE + ".tmp"]:
		if FileAccess.file_exists(dir.path_join(name)):
			DirAccess.remove_absolute(dir.path_join(name))
