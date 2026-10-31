import WeftCore

/// Tiddlers weft comes with, as TiddlyWiki has its shadow tiddlers: shown
/// when the wiki has none of their title, and written to it only when
/// edited — then the wiki's own.
enum ShadowTiddlers {
    static let gettingStarted = "Getting Started"

    static let all: [String: Tiddler] = [
        gettingStarted: Tiddler(title: gettingStarted, tags: ["Weft"], text: """
        Weft keeps small notes — *tiddlers* — in your Reflect graph's `wiki/` folder, one Markdown file each, synced with the rest of the graph. This tiddler is built in: edit it, and it becomes one of yours.

        ## Making tiddlers

        - **⌘N**, or **+** above the river, makes one. Its title is how you link to it.
        - Double-click a title, or the pencil, to edit. **⌘↩** saves; **Escape** cancels.
        - Tag it in the editor. A tag is a tiddler too: its card lists everything tagged with it.

        ## Linking

        Type `[[` and choose a title. A link can go to a tiddler, to one of your Reflect notes by its title or alias, or to a day, like [[2026-10-31]] — they open as cards beside this one. A link to a tiddler no one has written yet is faded; its card offers to write it.

        `![[Title]]` shows another tiddler inside this one, live.

        > [!TIP]
        > Follow a link and its card opens just after the card it was in, so the river reads as the path you took.

        ## Lists that keep themselves

        **Insert Query** in the editor makes a query: a list, table, set of cards or tree of the tiddlers it finds, kept up to date. These are the tiddlers changed last:

        ```query
        sort: -modified
        limit: 8
        ```

        ## Fields

        A tag can give what it tags fields of their own — a date, a link, a choice. Edit a tag's tiddler and choose **Give Tiddlers Tagged … Fields**.

        ## Keeping in step

        Weft commits what you write half a minute after you stop, and syncs with GitHub when it opens, when it comes to the front, and on **⌘R**. Where two devices changed the same lines, the card shows both, for you to choose.
        """),
    ]
}
