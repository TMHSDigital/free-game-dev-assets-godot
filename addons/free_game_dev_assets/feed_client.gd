@tool
extends Node
## Loads the catalog feed and reports what it got through `loaded`.
##
## - Uses the cached copy when it is under a day old (unless forced).
## - Otherwise sends a conditional request (If-None-Match / If-Modified-Since);
##   a 304 keeps the cached copy and marks it fresh.
## - When the request fails, or the feed is too new or broken, it falls back to
##   the cached copy and says why; with no cache it reports the problem.

## state: {"feed": Dictionary ({} when there is none), "source": "network" | "cache" | "none", "message": String}
signal loaded(state: Dictionary)

const Feed := preload("feed.gd")
const Cache := preload("feed_cache.gd")

const TIMEOUT_SEC := 20.0
const USER_AGENT := "free-game-dev-assets-godot (+https://github.com/TMHSDigital/free-game-dev-assets-godot)"

## Folder for the cached feed. The dock sets it to the editor's cache folder.
var cache_dir := ""
var url := Feed.URL

var _http: HTTPRequest
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	_http.accept_gzip = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func is_busy() -> bool:
	return _busy


## Loads the feed. `force` skips the once-a-day rule (the Refresh button).
func refresh(force := false) -> void:
	if _busy:
		return
	var cached := _cached()
	var meta := Cache.read_meta(cache_dir)
	if not force and cached["ok"] and Cache.is_fresh(meta, _now()):
		loaded.emit(_state(cached["feed"], "cache", ""))
		return
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT])
	# Validators only make sense when there is a cached body to fall back on.
	if cached["ok"]:
		if String(meta.get("etag", "")) != "":
			headers.append("If-None-Match: " + String(meta["etag"]))
		if String(meta.get("last_modified", "")) != "":
			headers.append("If-Modified-Since: " + String(meta["last_modified"]))
	_busy = true
	var err := _http.request(url, headers)
	if err != OK:
		_busy = false
		_fall_back(cached, "the request could not start (error %d)" % err)


func _on_request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var cached := _cached()
	if result != HTTPRequest.RESULT_SUCCESS:
		_fall_back(cached, "offline or unreachable (%s)" % _result_text(result))
		return
	if code == 304 and cached["ok"]:
		var meta := Cache.read_meta(cache_dir)
		meta["fetched_at"] = _now()
		Cache.write_meta(cache_dir, meta)
		loaded.emit(_state(cached["feed"], "cache", ""))
		return
	if code != 200:
		_fall_back(cached, "the catalog answered HTTP %d" % code)
		return
	var text := body.get_string_from_utf8()
	var parsed := Feed.parse(text)
	if not parsed["ok"]:
		_fall_back(cached, parsed["error"])
		return
	Cache.write(cache_dir, text, {
		"etag": _header(headers, "etag"),
		"last_modified": _header(headers, "last-modified"),
		"fetched_at": _now(),
	})
	loaded.emit(_state(parsed["feed"], "network", ""))


func _fall_back(cached: Dictionary, why: String) -> void:
	if cached["ok"]:
		var version := String(cached["feed"].get("version", ""))
		loaded.emit(_state(cached["feed"], "cache", "Showing saved data from %s: %s." % [version, why]))
	else:
		loaded.emit(_state({}, "none", "Could not load the catalog: %s." % why))


func _cached() -> Dictionary:
	var text := Cache.read_text(cache_dir)
	if text == "":
		return {"ok": false}
	# A cache written by a newer plugin version can be too new for this one.
	return Feed.parse(text)


func _state(feed: Dictionary, source: String, message: String) -> Dictionary:
	return {"feed": feed, "source": source, "message": message}


static func _header(headers: PackedStringArray, name: String) -> String:
	var prefix := name.to_lower() + ":"
	for h in headers:
		if h.to_lower().begins_with(prefix):
			return h.substr(prefix.length()).strip_edges()
	return ""


static func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "no connection"
		HTTPRequest.RESULT_TIMEOUT:
			return "timed out"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS error"
		_:
			return "request error %d" % result


func _now() -> float:
	return Time.get_unix_time_from_system()
