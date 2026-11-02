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
GitHub… and File ▸ Open Folder… (⇧⌘O) switch. `-GraphPath <folder>` skips
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
  scrolled to. Cards fold to their titles — on the Mac by the chevron
  in the margin before the title (⌥-click folds or opens every card) or
  ⌃⌘↑ and ⌃⌘↓ (when not writing in an outline); on the phone by a tap on the title — and a folded card
  shows its first line and how many more; pinching the river in folds
  every card, out opens them, as Fold All and Unfold All do (the Story
  menu, ⌃⌥⌘↑ ⌃⌥⌘↓, or ⋯ on the phone). A river keeps its folds. Cards
  close (×), and
  are dragged by their titles to elsewhere in the river — on the phone,
  held first — a line in the gap saying where; one dragged from another
  window's river is opened there. On the Mac, with the sidebar shut, the
  river's right edge is a map of it: a tick for each card, under the
  pointer their titles; one clicked is scrolled to, one dragged is moved,
  and a card dragged from the river over it is put where it is let go. On
  the iPhone, the sidebar and the river take turns.
- **Rivers**: more than one river can be open. On the Mac each is a tab in
  the window's title bar, as Safari's are, filling what the toolbar's
  buttons leave of it from the sidebar's button on — the one shown standing
  as the title, a click on it Quick Open; the others named, a slanted name
  for a river not saved. When they would not show their names, the others
  bunch to their icons, the one under the pointer opening out to its name. ⌘T opens one, with Quick Open showing; ⌘W closes
  it (⌥⌘W the window); ⇧⌘[ ⇧⌘] and ⌘1–9 go between them; a tab is dragged
  to another place, and from its menu saved, closed with the others, or
  moved to a window of its own (⇧⌘N opens a new window). With one river,
  the title is its name, the graph under it. A page open in two tabs is
  one draft in both. On the phone, the bar at the foot of the river says which
  it is: its menu lists the rivers open and makes a new one, and a swipe on
  it goes between them. There is no bar at the top: the river runs up under
  glass controls — back to the sidebar, Quick Open, Today, and a menu —
  which step aside as it is read down, the bar at the foot gathering to the
  river's name, as Prism's do.
  A river is this device's alone, remembered per graph, until it is saved
  under a name (Story ▸ Save River…, or the stack button above the river):
  then it is a file in the graph's `rivers/` folder — a link to each card a
  line — synced with the rest and kept as its cards change. What is folded
  goes with it: the cards folded to their titles in its frontmatter
  `folded:`, and the rows folded in each card under its link (`  - 4: Row
  text`, the row's place and words), so a river folded on the Mac opens
  folded so on the phone, and refolds as a sync brings the change. Each
  river keeps its own folds — a page open in two folds in each as it was
  left there — and one new to a page opens it as it was folded last on
  this device. A saved river is not opened anywhere until it is brought
  back from **Saved Rivers** (⇧⌘R, or the bar's menu on the phone), which
  also duplicates, renames and deletes them; deleting one leaves its cards
  open where they are.
  A page links to a saved river as to the file it is — `[[rivers/Work]]`,
  shown as **Work** with a stack before it — and a tap on the link brings
  the river back: to the front where it shows, else beside. Renaming the
  river rewrites the links to it; one to a river deleted is drawn faint.
  `[[` offers the saved rivers its words name; a tab dragged into a card
  writes a link to its river there (an unsaved river's cards, a link a
  row); and **Copy Link to River** is in a tab's menu, the phone's river
  menu, and each saved river's. Quick Open finds saved rivers by name; a card shows,
  under what it is related to, the other saved rivers it is a card of
  (**In Rivers**); and Saved Rivers says how many pages link to each,
  listed in its menu. From outside the graph — a reminder, a message, Prism —
  `weft://river/Work` brings the river back in Weft, on the Mac or the
  phone; **Copy River Address** gives it. Embedded alone in its line —
  `![[rivers/Work]]` — a river is drawn as its name and its cards, each a
  link: a page of rivers, a dashboard of what is under way. A page may
  name its home river in its frontmatter — `river: Work`, from **Home
  River** in its card's menu — shown beside its title, a tap bringing the
  river back. Prism reads river links too: shown by the river's name, an
  embed its cards; followed, the river comes back in Weft — or, without
  Weft, Prism opens its file.
- **A card** is written in where it stands — there is no Edit and no
  Preview. Its body reads as what it says, and is edited as it reads: as
  an **Outline** (Prism's outline editor, the Mac's and the phone's) where
  the outline would write it back as it is, else as **Text** (Markdown,
  its markup showing only on the lines the caret is on) — the switch in
  its header (on the Mac, two icons: lines of text, and an indented list), or on the phone in its menu. In both, links and tags are pills, as Slack draws them: an
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
  italic and a link; ⌘↩ makes the row or line a checklist item, then
  checks it, then makes it a plain item again (Format ▸ Checklist Item), and
  ⇧⌘↩ a task, as Prism's do. An outline takes all of Prism's keys while
  the caret is in it — ⇧⌘K deletes rows, ⇧⌘D duplicates them, ⌃⌘↑ ⌃⌘↓
  move them and ⌃⌘→ ⌃⌘← indent them, ⌘9 and ⌘0 fold and unfold them, and
  the rest of Prism's Format, Outline and Selection menus — over the
  river's own keys that share one. Tags offer the ones already in use. Escape takes the
  caret out. A save writes only what changed in the file.
- **Quick Open** (⌘O): a tiddler, note or day by what is typed — today and
  the tiddlers written last, with nothing typed — opened in the river (⌘↩
  on the Mac, in a tab of its own); or a new tiddler of that name. Set as
  Prism's Go to is: on the Mac a card of paper over the river, each row a
  name and when it was written; on the phone a sheet, each row its kind,
  its name, and under it when.
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
  title, then an alias — and opens it as a card, written in as any is. A
  note's card shows its #tags, its body, and what links to it; a tiddler's
  card lists the notes linking to it. Search finds notes too, as Reflect's
  chooser does. Today (⇧⌘T) opens today's note. Private notes never show.
  A day's card has ‹ › for the day before and after, opened just after
  it (⌥⌘[ and ⌥⌘]); Quick Open finds a day by a few words too — `friday`,
  `next week`, `3 days ago`, `Jan 3`. On the phone, a task's menu moves it
  into a day: Do Today, or Later…
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
- **Back and forward**: ⌘[ goes back to the card the river was at before
  a link was followed or a card opened — opened again if it was closed —
  and ⌘] forward again; on the phone, the ‹ at the top, held, lists them.
- **On the phone**: the river pulled down syncs; a card moved or closed,
  or the river changed, is felt as a tick. On the iPad, a keyboard has the
  Mac's keys.
- **Pictures**: pasted into a card, or dropped on one on the Mac, kept in
  the graph's `assets/` as Prism keeps them, and shown where the caret is.
- **Finding**: ⌘F finds words in the card being written in (Find in Card
  in its menu, too), else goes to the sidebar's search, where each page
  found shows the line it was found in, what was typed marked; ⌥⌘F always
  goes there.
- **Undo**: a page deleted, cards closed, a tag or field taken off — each
  undone with ⌘Z, or the Undo offered for a moment at the foot of the river.
- **Settings** (⌘, on the Mac; ⋯ ▸ Settings… on the phone): the size cards
  are set in; on the phone, the outline's face, and the GitHub account.
- On the iPad, each window has rivers of its own.
- **Related pages**, without a link in the text: Relate To… in a card's
  menu, or the + under its **Related**, names another page in the card's
  frontmatter `related:` list — Prism's own, read and written by both. A
  relation shows on both cards (↩ on the one it isn't written in); a pill
  opens its card after this one, and its menu unrelates it, from whichever
  page has it written.
- **Prism's lenses** in the sidebar: the **Inbox**, **Tasks** (every
  open `+ [ ]`, grouped as Prism groups them, each ticked off where it
  stands) and **Pinned**; a card's menu puts it in the inbox, or pins it.
- **Reading**, as Prism reads: **Read** in a card's menu shows the pages it
  links to — a link note's own first, ‹ › to the rest — its words alone,
  set in Chronicle, or the site; where it was read to is kept. A passage
  chosen and highlighted (⇧⌘H) is written into the card under the link, and
  marked whenever the page is read again. The sidebar's **Reading** tab is
  Prism's Reading Queue: the pages saved to read, oldest first, each read
  with **Done** or **Later** at its foot. On the Mac the reader is beside
  the river; on the phone, over it.
- **History**: a card's menu has **History…** — each version of the page in
  the graph's history, one put back with Restore — and **Recently
  Deleted…** (the File menu, or ⋯ on the phone) brings back pages deleted.
- ⌘N makes a new tiddler, its made-up title selected to type over; ⇧⌘W
  closes every card not being edited.

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
  WEFT_RIVERS=1 WEFT_FOLD="A|B" WEFT_DELAY=3`, or an onboarding page with
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
