import WeftCore

/// Tiddlers weft comes with, as TiddlyWiki has its shadow tiddlers: shown
/// when the wiki has none of their title, and written to it only when
/// edited — then the wiki's own.
enum ShadowTiddlers {
    static let gettingStarted = "Getting Started"

    static let all: [String: Tiddler] = [
        gettingStarted: Tiddler(title: gettingStarted, tags: ["Weft"], fields: [Tiddler.Field("wiki", .text("true"))], text: """
        Weft keeps small notes — *tiddlers* — in your Reflect graph, one Markdown file each, beside your notes and days and synced with them. This tiddler is built in: write in it, and it becomes one of yours.

        ## Making tiddlers

        - **⌘N**, or **+** above the river, makes one. Its title is how you link to it.
        - Click into a card to write in it — there is no separate editor. A card is written as an **Outline** of rows, as Prism writes, unless it holds what an outline would change; then as **Text**, its Markdown showing on the line the caret is on. The switch in its header, or **⌘↩**, goes between them.
        - What you write saves itself. Double-click a title to rename it; **Escape** takes the caret out.
        - Tag it with **+** by its tags, or **Add Tag** in its menu. A tag is a tiddler too: its card lists everything tagged with it.

        ## Linking

        Type `[[` and choose a title. A link can go to a tiddler, to one of your Reflect notes by its title or alias, or to a day, like [[2026-10-31]] — they open as cards beside this one. A link to a tiddler no one has written yet is faded; its card offers to write it.

        `![[Title]]` shows another tiddler inside this one, live.

        > [!TIP]
        > Follow a link and its card opens just after the card it was in, so the river reads as the path you took. **⌘[** goes back along it, **⌘]** forward; on the phone, hold the ‹ at the top.

        Drag a card by its title to put it elsewhere in the river — on the phone, hold it first. A day's card has ‹ › for the day before and after.

        ## More than one river

        On the Mac, **⌘T** opens another river in a tab; on the phone, the bar at the river's foot names it, and its menu makes another. Save a river under a name to keep it in the graph, synced — then bring it back from **Saved Rivers**, where it can be duplicated, renamed or deleted.

        ## Lists that keep themselves

        **Insert Query** in a card's menu makes a query: a list, table, set of cards or tree of the tiddlers it finds, kept up to date. These are the tiddlers changed last:

        ```query
        sort: -modified
        limit: 8
        ```

        ## Fields

        A tag can give what it tags fields of their own — a date, a link, a choice. In the tag's card, choose **Fields of Tiddlers Tagged …** from its menu.

        ## Keeping in step

        Weft commits what you write half a minute after you stop, and syncs with GitHub when it opens, when it comes to the front, and on **⌘R** — or, on the phone, when the river is pulled down. Where two devices changed the same lines, the card shows both, for you to choose.
        """),
    ]
}
