# Free Game Dev Assets for Godot

A Godot 4 editor plugin for the [Free Game Dev Assets](https://tmhsdigital.github.io/Free-Game-Dev-Assets/) catalog. The plugin is not built yet; see the roadmap below.

Planned features:

- browse the catalog in an editor dock
- filter by licence, commercial use, credit requirements and whether an asset works in Godot
- open the source or the entry's catalog page, where the licence is quoted
- copy the recorded credit line
- export a `CREDITS.md` for the assets your project uses

The catalog records each licence as it read on a given date. Check the source before you ship.

## Status

Early development. Planned work is tracked in [TMHSDigital/Free-Game-Dev-Assets#116](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/116):

- [x] Plugin feed published by the catalog build ([#277](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/277))
- [x] Skeleton addon with an empty dock ([#278](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/278))
- [x] Fetch and cache the feed, offline fallback ([#279](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/279))
- [ ] Browse list with search and filters ([#280](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/280))
- [ ] Entry details and actions ([#281](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/281))
- [ ] Project asset list and `CREDITS.md` export ([#282](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/282))
- [ ] Tests in CI ([#283](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/283))
- [ ] Release and Asset Library listing ([#284](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/284))

## Requirements

Godot 4.3 or later. GDScript only: no GDExtension and no C#.

## Install (once released)

From the Godot Asset Library, or by copying `addons/free_game_dev_assets/` into your project. Then turn it on under **Project → Project Settings → Plugins**.

## Develop

The repo root is a small Godot project with the plugin turned on. Open the folder in Godot 4.3 or later and the "Free Assets" dock appears on the right. To check from a terminal that it loads cleanly:

```
godot --headless --editor --quit-after 120 --verbose --path .
```

The output should include `free_game_dev_assets: dock added` and no `SCRIPT ERROR`. `project.godot` is left out of the Asset Library download.

Unit tests (no network, no editor):

```
godot --headless --path . --script tests/run_tests.gd
```

The plugin reads [`plugin-feed.json`](https://tmhsdigital.github.io/Free-Game-Dev-Assets/plugin-feed.json) ([format notes](https://github.com/TMHSDigital/Free-Game-Dev-Assets/blob/main/docs/data.md#plugin-feed)). It caches the feed in the editor's cache folder, not in your project, and checks for a newer one at most once a day, or whenever you press Refresh.

## Licence

Plugin code: [MIT](LICENSE). Catalog data: [CC0 1.0](https://github.com/TMHSDigital/Free-Game-Dev-Assets/blob/main/LICENSE). The assets the catalog lists keep their own licences.
