# Weft

TiddlyWiki's ideas — small titled notes, a river of cards, tags as
structure, transclusion, lists made by filters — as a native app on the
Mac, the iPad and the iPhone, kept in a Reflect graph's `wiki/` folder and
synced with it by Reflect's own sync. See [DESIGN.md](DESIGN.md).

## Building

```sh
scripts/build-app.sh                            # build/Weft.app
scripts/build-app.sh run -GraphPath ~/reflect   # and open it on a graph
swift test
```

The first launch is onboarding: what weft is, then where the graph is.
**Connect to GitHub** signs in with the same GitHub App as Prism, and
brings the graph's repository down into weft's own folder
(`~/Library/Application Support/Weft/Graph` on the Mac), synced through
libgit2 with the account — as the phone does, and as Prism does. On the
Mac, **Use a Folder on This Mac** opens a checkout already there, such as
Reflect Mac's, synced through the Mac's own `git`. Later, File ▸ Connect to
GitHub… and File ▸ Open Folder… (⌘O) switch. `-GraphPath <folder>` skips
onboarding and opens that folder.

The GitHub App's details come from reflect-mac's `iOS/GitHub.local.xcconfig`:
read by `scripts/build-app.sh` on the Mac, included by the xcconfig of
`iOS/Weft.xcodeproj`, the iPhone and iPad app.

An empty wiki shows **Getting Started**, a tiddler built into weft, as
TiddlyWiki has shadow tiddlers: written to the graph only when edited.

## Trying it on TiddlyWiki's own documentation

```sh
curl -sSL -o /tmp/tw.html https://tiddlywiki.com/
mkdir -p /tmp/tw-graph
swift run weft import /tmp/tw.html /tmp/tw-graph
scripts/build-app.sh run -GraphPath /tmp/tw-graph
```

## The app

- **The river**: open cards, one after another. A link opens its card just
  after the one it was clicked in and scrolls to it; a card already open is
  scrolled to. Cards fold to their titles (the chevron) and close (×). Which
  cards are open is remembered per graph, on this device only. On the
  iPhone, the sidebar and the river take turns.
- **A card**: its title, tag pills (click one to open the tag's card), its
  body, what is tagged with it, its other fields, and what links to it.
  Links to tiddlers that don't exist yet are faded; their card offers to
  create them. `![[Title]]` shows the other tiddler inside, live.
- **Queries**: a ```` ```query ```` block lists the tiddlers it finds —
  tagged with something, linking to something, listed in a tiddler's `list`,
  with words in them — as a list, a line of links, a table, cards, a count,
  or a table-of-contents tree. **Edit Query** on the card changes it with a
  form; **Insert Query** in the editor makes one. `{this}` stands for the
  tiddler it's in. The importer turns TiddlyWiki's `<<list-links>>`,
  `<<toc>>`, `<$list>` and `{{{ }}}` into queries where their filters allow.
- **Editing**: the pencil, or double-click the title. The body is Markdown,
  styled as it is typed: links are tokens (faint brackets, a missing tiddler
  slanted), emphasis and headings show, markup is faded. Typing `[[` offers
  titles (the completion list on the Mac, a bar above the keyboard on the
  phone). The formatting bar does bold, italic, code, headings, lists,
  links, embeds and callouts. Tags offer the ones already in use. ⌘↩ saves,
  Escape cancels; a save writes only what changed in the file.
- **Sync**: Reflect's own — commit thirty seconds after writing stops, a
  full sync at launch, on coming to the front, and on ⌘R. The Mac syncs the
  graph's checkout with its own `git`; the phone its clone with libgit2 and
  the GitHub account. Two devices' changes to one tiddler have their
  frontmatter merged field by field (tags as sets, the later `modified`)
  before the bodies are merged by lines. Where both changed the same lines,
  the card shows both sides with **Keep This Device's**, **Keep the Other
  Device's** and **Keep Both**, and the toolbar says how many need review.
  A draft saved over a tiddler a sync changed meanwhile is merged with it.
- **Reflect notes and days as cards**: a `[[link]]` no tiddler answers
  leads where Reflect would take it — a date to its day, then a note's
  title, then an alias — and opens it as a card, read-only for now. A
  note's card shows its #tags, its body, and what links to it; a tiddler's
  card lists the notes linking to it. Search finds notes too, as Reflect's
  chooser does. Today (⌘T) opens today's note. Private notes never show.
- **Typed tags**: a tag tiddler's `fields` list — `birthday (date)`,
  `company (link)`, `status (active | paused | done)`, `rating (number)`,
  `website (url)`, `met (yes/no)`, or a bare name for text — gives every
  tiddler tagged with it those fields: shown as a panel by kind (a date
  links to its day), edited with a date picker, a menu, a toggle, a field
  offering titles. The tag's card has **New *Tag***, and a query table of
  it shows those fields as columns. The tag's editor edits the list.
- **Renaming and deleting**: renaming a tiddler updates the tiddlers that
  name it — links, embeds, tags, `list` fields, query blocks, link fields —
  unless the editor's toggle says not to. **Delete Tiddler…** in a card's
  menu asks first; the graph's history keeps it.
- **Instant sync**: signed in to GitHub (File ▸ GitHub Account… on the Mac;
  the phone signs in to clone), weft follows the sync relay and syncs as
  soon as another device pushes. The phone also registers for the relay's
  silent pushes, to sync in the background.
- **The sidebar**: search (⌘F) over titles, then text, then Reflect notes;
  Open, Recent, Tags, and Missing (links to tiddlers no one has written).
- ⌘N makes a new tiddler; ⇧⌘W closes every card not being edited.

WikiText the importer couldn't convert shows as a dashed placeholder, the
WikiText a click away.

## Code

- `Sources/WeftCore` — no UI. `Tiddler` and `TiddlerFile` (the file format),
  `Wiki` (every tiddler, links, tags), `MarkdownBlock` (a body as blocks to
  show), `Query`, `FieldSpec` (typed tags), `Relink`, `ReflectNotes` (the
  graph's notes, through reflect-mac's `NoteIndex`), `TiddlerMerge` and
  `WikiSync` (the sync, over reflect-mac's `Git`), `TiddlyWiki/` (the import).
- `Sources/WeftUI` — the views, for the Mac and the phone: `WikiStore` (the
  graph, the river, drafts, the sync), `ContentView` (sidebar and river),
  `Card`, `CardEditor`, `MarkdownView`, `QueryView`, `ConflictView`, and
  `Editor/` (the text view, its styling and completion).
- `Sources/WeftGitHub` — GitHub: a graph cloned into weft's own folder and
  synced with libgit2 (reflect-mac's `ReflectGit2`), signing in and
  choosing it (`GitHubConnect`), onboarding, and the sync relay, followed.
- `Sources/WeftMac` — the Mac app around them. `Snapshot` draws the window
  to a PNG for checking the app without a person at it:
  `WEFT_SNAPSHOT=out.png WEFT_OPEN="A|B" WEFT_EDIT=A WEFT_DELAY=3`, or an
  onboarding page with `WEFT_ONBOARDING_STEP=place`. It never syncs.
- `iOS/Weft` — the iPhone and iPad app around them, and signing in to GitHub.
- `Sources/weft` — the command line: `weft import`, `weft show`.

weft needs two things of reflect-mac, both in `ReflectCore`: `Git.prepareMerge`,
the hook the tiddler merge goes through, and commit messages that name
tiddlers by title (`Update HelloThere`).
