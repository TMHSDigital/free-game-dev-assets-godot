@tool
extends RefCounted
## What the details panel shows for one entry, and which links it may open.
## No nodes and no editor APIs, so the tests can run it headless.
##
## Field meanings follow the catalog's docs/data.md: `commercial` is true,
## false, "varies" or "unknown"; `attribution_required` is true, false or
## "unknown"; `attributionClass` "notice" means carry the licence text with
## the files; `credit_line` may hold {…} parts for the user to fill in.


## True for an https:// URL with a host and no spaces or control characters.
## Anything else (http, file, javascript, a bare path) is never opened.
static func is_https(url) -> bool:
	if typeof(url) != TYPE_STRING or not url.begins_with("https://"):
		return false
	for i in url.length():
		var code: int = url.unicode_at(i)
		if code <= 0x20 or code == 0x7f or code == 0x5c:  # control, space, DEL, backslash
			return false
	var host := String(url).substr(8).get_slice("/", 0)
	return host != ""


## The entry's source URL, or "" when it is not safe to open.
static func source_url(e: Dictionary) -> String:
	var url = e.get("url")
	return url if is_https(url) else ""


## The entry's page on the catalog site (where the licence is quoted), or ""
## when the feed's page path doesn't look like a plain relative path.
static func catalog_page_url(feed: Dictionary, e: Dictionary) -> String:
	var site = feed.get("siteUrl")
	var page = e.get("page")
	if not is_https(site) or typeof(page) != TYPE_STRING:
		return ""
	var path_ok := RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9._~/-]*$")
	if path_ok.search(page) == null or page.contains(".."):
		return ""
	return String(site).trim_suffix("/") + "/" + page


static func licence_text(e: Dictionary) -> String:
	var licence := String(e.get("license", ""))
	var spdx = e.get("license_spdx")
	if typeof(spdx) == TYPE_STRING and spdx != "" and spdx != licence:
		return "%s (%s)" % [licence, spdx]
	return licence


static func commercial_text(value) -> String:
	if typeof(value) == TYPE_BOOL:
		return "Yes" if value else "No"
	if typeof(value) == TYPE_STRING and value == "varies":
		return "Varies by file"
	return "Unknown: check the source"


## What to say about credit, and whether there is a line to copy.
## Returns {text, can_copy, line, note, fill_in}.
static func credit(e: Dictionary) -> Dictionary:
	var line = e.get("credit_line")
	var has_line: bool = typeof(line) == TYPE_STRING and line.strip_edges() != ""
	# "unknown" and anything unexpected count as unknown.
	var required = e.get("attribution_required")
	if typeof(required) != TYPE_BOOL:
		required = null
	var out := {"text": "", "can_copy": has_line, "line": line if has_line else "", "note": "", "fill_in": false}
	if required == null:
		out["text"] = "Unknown: check the source"
	else:
		out["text"] = "Required" if required else "Not required"
	if String(e.get("attributionClass", "")) == "notice":
		out["text"] += "; keep the licence text with the files"
	if has_line:
		out["fill_in"] = line.contains("{")
		if out["fill_in"]:
			out["note"] = "Fill in the {…} parts after pasting."
	elif required == false:
		out["note"] = "No credit is required for this entry."
	elif required == true:
		out["note"] = "Credit is required, but no credit line is recorded: see the catalog page."
	else:
		out["note"] = "The catalog doesn't know whether credit is required: see the catalog page."
	return out


static func verified_note(e: Dictionary) -> String:
	var date = e.get("verified")
	if typeof(date) == TYPE_STRING and date != "":
		return "Licence as recorded on %s. Check the source before you ship." % date
	return "Licence as recorded by the catalog. Check the source before you ship."
