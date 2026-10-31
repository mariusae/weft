# Weft

TiddlyWiki's ideas — small titled notes, a river of cards, tags as structure,
transclusion, filters, templates — as a native app on the Mac, the iPad and the
iPhone, with each concept given its own affordance instead of markup. Kept in
the same git repository as the Reflect graph, and synced the same way.

## Decisions so far

- **Prose, not outlines.** A tiddler's body is prose, as in TiddlyWiki.
- **The Reflect graph is the wiki's home.** Tiddlers live in `wiki/` in the
  Reflect graph's checkout, next to `daily/`, `notes/` and `assets/`. One
  repository, one sync engine, one conflict review, one relay, and a tiddler
  can link to a Reflect note or day as easily as to another tiddler.
- **Sync is reflect-mac's, literally.** Weft depends on `ReflectCore` and
  `ReflectGit2` from `../reflect-mac` (a local SwiftPM package) rather than
  copying them. Whatever weft needs that they don't have is added there, in
  terms general enough for both apps.
- **Test content comes from TiddlyWiki's own sites** (see Import).

## The model

A tiddler is a Markdown file with YAML frontmatter:

```markdown
---
id: 01JBXK3T6Y8Q2ZP4M9V7C5R0WD
title: HelloThere
tags: [Welcome, "Table of Contents"]
created: 2026-10-31T10:34:00Z
modified: 2026-10-31T10:41:12Z
caption: Hello
---
Welcome to [[TiddlyWiki]], a unique non-linear notebook…
```

- `title` is the identity people see and link by; `id` (a ULID, as Reflect
  gives its notes) is the one that survives renames.
- The file is `wiki/<slug>.md`. The slug is only a place to keep the file: a
  title with `/` in it (117 of tiddlywiki.com's) or a slug already taken
  (`@Jermolene` and `Jermolene`) gets `-2`, `-3`. Renaming a tiddler leaves
  its file where it is.
- Any other frontmatter key is a field (`caption`, `description`, `url`,
  `color`, …), as in TiddlyWiki.
- Reading a file and writing it back unchanged gives the same bytes, as in
  reflect-mac.
- Pictures and other files go in the graph's `assets/`, by reflect-mac's
  naming rules.

### Native affordances instead of markup

| TiddlyWiki | In the file | On screen |
|---|---|---|
| `[[Link]]` | `[[Link]]` | a link token; a missing tiddler drawn differently, made on click |
| tags field | `tags:` | pills on the card, drag to reorder (writes the tag's `list`) |
| other fields | frontmatter keys | a properties panel on the card |
| `{{Title}}` transclusion | `![[Title]]` | the other tiddler, live and editable, inline |
| filter + list widget | a fenced ```` ```query ```` block | a query builder; shown as a list, table or board |
| view templates, cascade | a tag tiddler's frontmatter | "tagged *Person*": these fields, this layout |
| `$:/config/…` | `wiki/$config/…` (or the app's settings) | settings that are tiddlers, defaults built in |

### Links across the graph

One namespace for `[[…]]`: a tiddler's title, then a date (`[[2026-10-31]]`
is that day's daily note), then a Reflect note's title or alias, the way
reflect-mac resolves links. A Reflect note or day opens as a card in the river
— read-only at first, later with reflect-mac's outline editor inside the card.

## The interface

- **The river**: the open cards in one column. A link opens its card just
  after the one it was clicked in, and the river scrolls to it; a card already
  open is scrolled to instead. Cards close, collapse to their title, switch
  between viewing and editing in place, and can be dragged into a new order.
- **The sidebar**: search, Open, Recent, Tags, and later Missing and Orphans.
- **Each card**: title, tag pills, body, properties when there are any,
  backlinks at the bottom.
- **The Mac and the iPad**: sidebar and river side by side, keyboard first;
  on a wide window, more than one column of cards.
- **The iPhone**: a stack of cards. A link pushes a card; swiping moves
  between the open ones; cards collapse to their titles to be scanned.
- Which cards are open is how this device shows the wiki, not what the wiki
  says: it is kept per device, out of the repository, and handed on between
  devices by Handoff.

## Sync

Exactly reflect-mac's: commit a moment after typing stops, fetch, merge and
push at launch, on coming to the front and on demand; the relay wakes the
other devices; a merge never stops the sync; conflicts are marked and
reviewed. What weft needs added to the shared code:

- **Commit messages** that name tiddlers: `Update HelloThere`, `Add 3 tiddlers`.
  Today a `wiki/` file counts as "a file" (`CommitMessage.noteLabel` only
  knows `daily/` and `notes/`).
- **Notes needing review** that include `wiki/` (`Graph.notesNeedingReview`
  only scans `daily/` and `notes/`).
- **Merging frontmatter field by field** before merging the body as text:
  tags merged as a set, `modified` the later of the two, other fields merged
  key by key. Without this, `modified` alone would make nearly every
  concurrent edit a conflict.

### Reflect itself

For now Reflect leaves the wiki alone. reflect-mac and Reflect's own note
scanner (`reflect-graph`'s `walk_notes`) only look in `daily/`, `notes/` and
`templates/`. Reflect desktop's file catalog (`graph-paths`' `walk_catalog`,
which its desktop app, iCloud check and CLI all use) lists every `.md` file,
but honours a `.reflectignore` in `.gitignore` syntax. So when weft first
makes `wiki/`, it adds `/wiki/` to the graph's `.reflectignore` (made if
there is none, and committed like anything else). Whether Reflect should see
tiddlers — one search across both — is for later.

## Import

TiddlyWiki keeps its tiddlers as JSON inside the HTML file
(`<script class="tiddlywiki-tiddler-store" type="application/json">`), so
reading them is easy; converting WikiText to Markdown is the work.

- **tiddlywiki.org**: 6 content tiddlers. A smoke test.
- **tiddlywiki.com**: 1,790 content tiddlers (not counting `$:/` system ones),
  using links (1,022), macros (964), bullets (417), widgets (407),
  transclusion (402), headings (374), code (226) and tables (173), plus 48
  `text/vnd.tiddlywiki-multiple` and a few images. This is the real test.

The converter handles the common WikiText (headings, lists, bold, italic,
links, transclusion, code, tables) and leaves anything it can't convert —
macros, widgets, filters in `{{{ }}}` — as written, in a fenced
```` ```tiddlywiki ```` block that the card shows as a placeholder. Each run
reports how many tiddlers converted fully, which gives a measure to improve
against. Imports go into a throwaway test graph, never the real one.

tiddlywiki.com's documentation is written with macros of its own
(`<<.def>>`, `<<.olink>>`, `<<.tip>>`, `<<wikitext-example>>`, …, defined in
`$:/editions/tw5.com/doc-macros`). For a wiki that defines them, the importer
rewrites them as the Markdown they come to: emphasis, code, links, callouts
(`> [!TIP]`), and an example's source beside what it renders as.

Where it stands (`weft import`): 866 of tiddlywiki.com's 1,790 tiddlers
convert completely. What's left is mostly what makes TiddlyWiki dynamic —
`<$list>`, `<$button>`, `<<list-links>>`, transclusion through templates —
and is the work for weft's native query blocks and typed tags, not for the
converter.

## Code

- `WeftCore` (no UI): the tiddler, reading and writing files, the store (every
  tiddler in memory, as TiddlyWiki does), links, tags and backlinks, the query
  engine, the TiddlyWiki import.
- `Weft`: one SwiftUI app for macOS 26 and iOS 26, with AppKit/UIKit where
  the editor needs it.
- From `../reflect-mac`: `ReflectCore` (graph, git, conflicts, commit
  messages) and `ReflectGit2` (libgit2, GitHub sign-in, relay).

## One graph with Prism

Reflect Mac is retired; Prism and Weft are the two apps on the graph. They
share GraphKit (in reflect-mac): pages and their files, the Markdown both
speak (reflect-mac's docs/markdown.md, with fixtures both test against),
the index, queries, typed fields, merging and the sync. Every page lives
where Prism keeps it — `daily/`, `weekly/`, `notes/` — and there is no
`wiki/`: a page in the wiki is one whose frontmatter says `wiki: true`.
Extensions are free to diverge from Reflect's, but each degrades to plain
Markdown.

Next: Prism on GraphKit — its notes read through `PageIndex`, its lenses as
queries, and callouts, query blocks, embeds and typed fields drawn in its
outline; Weft editing outline pages with Prism's outline editor.

## Where it stands

Built: the file format and import; the river, cards and sidebar on the Mac,
iPad and iPhone; query blocks; the native editor; sync through Reflect's
`Git`, with frontmatter merged field by field and conflicts reviewed on the
card; Reflect notes and days as read-only cards; typed tags; renaming with
relinking, and deleting; instant sync through the relay.

Next: Reflect notes edited in their card, with reflect-mac's outline
editor; queries over notes as well as tiddlers; a tiddler's history from
git, as TiddlyWiki's revisions.

## First steps (as planned)

1. `WeftCore`: the tiddler model and its file format, with round-trip tests.
2. The importer, run against tiddlywiki.com into a test graph: the format
   meets real content early.
3. A Mac prototype: sidebar and river over the imported wiki, cards viewed
   and edited as plain text. This is where we learn whether it feels right.
4. Sync through `ReflectGit2`, plus the three additions above.
5. The iPad and the iPhone.
6. The native affordances: link tokens, tag pills, properties, embeds, query
   blocks, typed tags.
