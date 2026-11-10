@tool
extends RefCounted
## Search, filters and sort for the browse list, and saving the filter state.
## No nodes and no editor APIs, so the tests can run it headless.

## Where the filter state is saved, inside the editor's config folder.
const SETTINGS_FILE := "free_game_dev_assets.cfg"
const _SECTION := "filters"


## The filters a fresh install starts with.
static func default_filters() -> Dictionary:
	return {
		"query": "",
		"category": "",         # "" means any
		"license_family": "",   # "" means any
		"commercial": false,    # only entries with commercial == true
		"no_credit": false,     # only entries with attribution_required == false
		"godot": true,          # only entries with "godot" in works_in
	}


## Returns the entries that pass `filters`, sorted: made for Godot first,
## then by name.
static func apply(entries: Array, filters: Dictionary) -> Array:
	var words := _words(String(filters.get("query", "")))
	var category := String(filters.get("category", ""))
	var family := String(filters.get("license_family", ""))
	var out: Array = []
	for e in entries:
		if category != "" and e.get("category") != category:
			continue
		if family != "" and e.get("licenseFamily") != family:
			continue
		if filters.get("commercial", false) and e.get("commercial") != true:
			continue
		if filters.get("no_credit", false) and e.get("attribution_required") != false:
			continue
		if filters.get("godot", false) and not e.get("works_in", []).has("godot"):
			continue
		if not words.is_empty():
			var hay := search_text(e)
			var hit := true
			for w in words:
				if not hay.contains(w):
					hit = false
					break
			if not hit:
				continue
		out.append(e)
	out.sort_custom(_before)
	return out


## The lower-case text the search box matches against: name, tags,
## publisher and summary.
static func search_text(e: Dictionary) -> String:
	var parts: PackedStringArray = [_str(e.get("name")), _str(e.get("publisher")), _str(e.get("summary"))]
	for t in e.get("tags", []):
		parts.append(_str(t))
	return " ".join(parts).to_lower()


static func made_for_godot(e: Dictionary) -> bool:
	return e.get("made_for", []).has("godot")


## Reads saved filters. Missing or wrongly typed values fall back to the defaults.
static func load_filters(path: String) -> Dictionary:
	var out := default_filters()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	for key in out:
		var v = cfg.get_value(_SECTION, key, out[key])
		if typeof(v) == typeof(out[key]):
			out[key] = v
	return out


static func save_filters(path: String, filters: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep any other sections
	for key in default_filters():
		if filters.has(key):
			cfg.set_value(_SECTION, key, filters[key])
	return cfg.save(path) == OK


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ga := made_for_godot(a)
	var gb := made_for_godot(b)
	if ga != gb:
		return ga
	return _str(a.get("name")).naturalnocasecmp_to(_str(b.get("name"))) < 0


static func _words(query: String) -> PackedStringArray:
	return query.to_lower().split(" ", false)


static func _str(v) -> String:
	return v if typeof(v) == TYPE_STRING else ""
