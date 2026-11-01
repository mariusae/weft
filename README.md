# Weft

TiddlyWiki's ideas — small titled pages, a river of cards, tags as
structure, transclusion, lists made by queries — as a native app on the
Mac, the iPad and the iPhone, over the same graph as Prism: every page in
it, days and notes alike, read and written by GraphKit, the core the two
apps share (`../reflect-mac/Sources/GraphKit`), in the Markdown both speak
(`../reflect-mac/docs/markdown.md`). See [DESIGN.md](DESIGN.md).

A page marked `wiki: true` is part of the wiki — canonical, kept up, an
evolving piece of knowledge — where other notes may be passing. That is
metadata only: Weft makes its new pages wiki pages, badges them, gathers
them in the sidebar's Wiki tab, and queries find them with `wiki: yes`.

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
  scrolled to. Cards fold to their titles (the chevron) and close (×). On
  the iPhone, the sidebar and the river take turns.
- **Rivers**: more than one river can be open. On the Mac each is a tab —
  ⌘T opens one, with Quick Open showing; a page open in two tabs is one
  draft in both. On the phone, the title's menu lists the rivers open and
  makes a new one, and the bar at the foot of the river swipes between them.
  A river is this device's alone, remembered per graph, until it is saved
  under a name (Story ▸ Save River…, or the stack button above the river):
  then it is a file in the graph's `rivers/` folder — a link to each card a
  line — synced with the rest and kept as its cards change. A saved river
  is not opened anywhere until it is brought back from **Saved Rivers**
  (⇧⌘R, or the title's menu on the phone), which also duplicates, renames
  and deletes them; deleting one leaves its cards open where they are.
- **A card** is written in where it stands — there is no Edit and no
  Preview. Its body reads as what it says, and is edited as it reads: as
  an **Outline** (Prism's outline editor, the Mac's and the phone's) where
  the outline would write it back as it is, else as **Text** (Markdown,
  its markup showing only on the lines the caret is on) — the switch in
  its header, ⌘↩ on the Mac, or on the phone in its menu. In both, links and tags are pills, as Slack draws them: an
  icon for a page, a day or the web, an address shortened to its site and
  the ends of its path; a click (or tap) follows one, and on the Mac a
  right-click opens or copies it. What is written saves itself a moment
  after typing pauses; when the caret leaves the card, a new title takes
  effect. Beside the
  switch, in a glass capsule, its menu (Rename, Fold, Close Others, Add
  Tag, Add Field, Insert Query, Copy Link, Show in Finder, Delete) and its
  close button. Story ▸ Write in Selected Card puts the caret in the
  selected card, or takes it out.
- **On a card**: its title (double-click to rename), tag pills (click one to
  open the tag's card; + adds one), its body, what is tagged with it, its
  other fields — and at its foot what links to it, as Manifold shows links:
  small faces bunched, dealt out under the pointer, each showing who links
  and the words around the link. Links to tiddlers that don't exist yet are
  faded; their card is there to write in. Under their lines, pictures, the
  card of a link alone in its line, `![[Title]]` — the other tiddler, live —
  and what a query finds.
- **Queries**: a ```` ```query ```` block lists the tiddlers it finds —
  tagged with something, linking to something, listed in a tiddler's `list`,
  with words in them — as a list, a line of links, a table, cards, a count,
  or a table-of-contents tree. **Insert Query…** in a card's menu makes one with a form. `{this}` stands for the
  tiddler it's in. The importer turns TiddlyWiki's `<<list-links>>`,
  `<<toc>>`, `<$list>` and `{{{ }}}` into queries where their filters allow.
- **Writing**: click into a card. Off the caret's lines, Markdown is drawn
  as what it means: headings, emphasis, code, quotes, bullets, links as
  tokens (a missing tiddler slanted) — the markup hidden. Typing `[[`
  finishes the title inline — the rest of the best one faint after the
  caret, Tab or → taking it — and lists tiddlers, notes, days and a new
  tiddler under the caret (↑↓, Return; Escape puts it away); on the phone,
  in the capsule of the bar over the keys. That bar is Prism's, on glass,
  in both modes: undo and redo, a line out and in, up and down, its tools
  (Text: a list, a checklist, a link, an embed, a callout; Outline:
  Prism's), Aa for bold, italic, struck, highlighted, code, a heading or a
  quote, and Done. ⌘B, ⌘I and ⌘K do bold,
  italic and a link. Tags offer the ones already in use. Escape takes the
  caret out. A save writes only what changed in the file.
- **Quick Open** (⌘O): a tiddler, note or day by what is typed — today and
  the tiddlers written last, with nothing typed — opened in the river; or a
  new tiddler of that name.
- **Colours**: Prism's — warm paper and ink, the cards lighter on a page a
  shade under them, its blue.
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
  chooser does. Today (⇧⌘T) opens today's note. Private notes never show.
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

- GraphKit, in reflect-mac — no UI, shared with Prism: `Page` and `PageFile`
  (pages and their files, titled by frontmatter or a `# Heading`),
  `PageIndex` (every page, names and aliases as Prism resolves them, links,
  backlinks, tags inline and in frontmatter), `MarkdownBlock`, `Query`,
  `FieldSpec` (typed tags), `Relink`, `PageMerge` and `GraphSync` (the sync,
  over `Git`). Its fixtures, `Tests/GraphKitTests/Fixtures`, are the
  Markdown spec's examples.
- `Sources/WeftCore` — what is Weft's own below the UI: TiddlyWiki's import
  (`TiddlyWiki/`), and TiddlyWiki's names for GraphKit's types (`Tiddler`
  for `Page`, `Wiki` for `PageIndex`, …).
- `Sources/WeftUI` — the views, for the Mac and the phone: `WikiStore` (the
  graph, editing and saving, saved rivers, the sync), `River` (one river's
  cards, selection and caret), `Rivers` (the phone's rivers, Saved
  Rivers), `ContentView` (sidebar and river), `Card`, `CardEditor`, `BacklinkFan`, `QuickOpen`,
  `MarkdownView`, `QueryView`, `ConflictView`, and `Editor/` (the text view,
  its styling, link pills and inline completion; the outline editor — on
  the Mac reflect-mac's `ReflectUI`, on the phone its `PhoneUI`, Prism's
  own, with its bar over the keys).
- `Sources/WeftGitHub` — GitHub: a graph cloned into weft's own folder and
  synced with libgit2 (reflect-mac's `ReflectGit2`), signing in and
  choosing it (`GitHubConnect`), onboarding, and the sync relay, followed.
- `Sources/WeftMac` — the Mac app around them. `Snapshot` draws the window
  to a PNG for checking the app without a person at it:
  `WEFT_SNAPSHOT=out.png WEFT_OPEN="A|B" WEFT_EDIT=A WEFT_TYPE="[[Ch"
  WEFT_FAN=0 WEFT_QUICK_OPEN=1 WEFT_TABS="A|B;C" WEFT_SAVE_RIVER=Work
  WEFT_RIVERS=1 WEFT_DELAY=3`, or an onboarding page with
  `WEFT_ONBOARDING_STEP=place`; panels open over the window are saved beside
  it. It never syncs, and never touches the GitHub account (the keychain).

`scripts/build-app.sh` signs with an Apple Development identity when there
is one, so the keychain knows each build as the same app and an Always
Allow for the GitHub sign-in holds; otherwise ad hoc.
- `iOS/Weft` — the iPhone and iPad app around them, and signing in to GitHub.
- `Sources/weft` — the command line: `weft import`, `weft show`.

weft needs two things of reflect-mac, both in `ReflectCore`: `Git.prepareMerge`,
the hook the tiddler merge goes through, and commit messages that name
tiddlers by title (`Update HelloThere`).
