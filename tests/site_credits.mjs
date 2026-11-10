// Writes the website's CREDITS file for the ids of a plugin feed, in feed
// order, using the website's own owes.js and data.json as deployed.
//   node tests/site_credits.mjs OWES.mjs DATA.json FEED.json OUT.md
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const [owesPath, dataPath, feedPath, outPath] = process.argv.slice(2);
if (!outPath) {
  console.error("usage: OWES.mjs DATA.json FEED.json OUT.md");
  process.exit(1);
}
const { owes, creditsFile } = await import(pathToFileURL(resolve(owesPath)).href);
const data = JSON.parse(readFileSync(dataPath, "utf8"));
const feed = JSON.parse(readFileSync(feedPath, "utf8"));
const byId = new Map(data.entries.map((e) => [e.id, e]));
const missing = feed.entries.filter((e) => !byId.has(e.id)).map((e) => e.id);
if (missing.length) {
  console.error(`in the feed but not in data.json: ${missing.join(", ")}`);
  process.exit(1);
}
// The same call as the site's shortlist export (site/public/shortlist.js),
// with no date so the two files can be compared.
const siteUrl = feed.siteUrl.replace(/\/+$/, "");
const text = creditsFile(owes(feed.entries.map((e) => ({ need: "shortlist", entry: byId.get(e.id) }))), {
  format: "md",
  pageUrl: (e) => `${siteUrl}/entry/${encodeURIComponent(e.id)}/`,
  date: "",
  source: "Free Game Dev Assets",
});
writeFileSync(outPath, text);
console.log(`site credits: ${feed.entries.length} entries, ${text.split("\n").length - 1} lines`);
