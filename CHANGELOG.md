# Changelog

All notable changes to the Free Game Dev Assets plugin for Godot. Versions follow
[semantic versioning](https://semver.org/); before 1.0.0, a minor version may change how the
plugin's files in your project (`free_game_dev_assets.json`, the `CREDITS.md` block) are written,
and the changelog will say so.

## Unreleased

### Fixed

- **Export credits** now says when it could not save `free_game_dev_assets.json`, instead of
  showing only the export result.
- **Only this project's** is no longer saved with the other filters. The filter settings are
  shared by every project, so it carried over and showed an empty list in other projects.

## 0.1.0 (2026-11-09)

The first release. Requires Godot 4.3 or later.

### Browse

- A **Free Assets** dock that lists the [Free Game Dev Assets](https://tmhsdigital.github.io/Free-Game-Dev-Assets/)
  catalog, entries made for Godot first.
- Search by name, tags, publisher and summary.
- Filters for category, licence family, commercial use, "no credit needed" and "works in Godot"
  (on by default), kept between editor sessions.
- The licence written on every row, on a background coloured by licence family. Columns size
  themselves so no licence id is cut short.

### Entry details

- Licence and SPDX id, commercial use (including "varies by file" and "unknown"), credit,
  formats, the date the licence was read, and the summary.
- **Open source** and **Catalog page** buttons. Only `https://` links are opened.
- **Copy credit line**, the line the catalog page shows, with a note when it has `{…}` parts to
  fill in. Turned off, with the reason, when there is no line to copy.

### Credits for your project

- **Add to project** keeps a list in `res://free_game_dev_assets.json`, to commit with the
  project.
- **Export credits** writes `res://CREDITS.md` with the same sections and lines as the website's
  shortlist export, between two markers, keeping your own text around them. Exporting again
  with nothing changed leaves the file as it is.
- Entries the catalog stops listing stay in `CREDITS.md` under "No longer listed", with the
  details from when the plugin last saw them.

### Network and storage

- One request, to the catalog's `plugin-feed.json`, at most once a day or on **Refresh**, with
  conditional headers so an unchanged catalog costs almost nothing. Works offline from the
  saved copy.
- The catalog is cached in the editor's cache folder and the filters in its config folder. The
  only files written in your project are the two above, and only when you add or export.
