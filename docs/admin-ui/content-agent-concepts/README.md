# Brando Assistant interface concepts

Three interactive mockups for the [content-agent scope](../../admin-content-agent-scope.md).
Implementation plan: [#2836](https://github.com/brandocms/brando/issues/2836).
These files are isolated design artifacts. They do not connect to a CMS, model
provider or MCP server, and every apply action is simulated.

Open **[concepts.html](concepts.html)** directly in a browser. It contains its own
fonts, artwork and photographs and works offline. Switch between the three
directions using the tabs at the top:

| Option | Interaction | Best fit |
| --- | --- | --- |
| A · Workspace **(selected)** | Conversation beside proposed changes or a page preview | Tasks across entries and repeated refinements |
| B · Visual board | A large media-led canvas, compact chat below | Reviewing asset placement across destinations |
| C · Guided review | One destination at a time, before/after placement | Occasional editors and deliberate review |

Try the media thumbnails, review links, field details, adjustment composer and
confirmation. C requires all three changes to be reviewed before enabling Apply.
New conversation resets the demo. Video previews use posters only. Sending an
adjustment captures text locally for demonstration; it does not generate changes.

In A, choose **Preview page** on a card. Switch between destination entries,
compare **Before / Proposed**, try desktop/mobile viewports and toggle change
highlighting. **All changes** returns to the overview. The apply bar always
describes all three entry changes. Open `concepts.html#workspace-preview` to
start directly in the page preview.

The page design is illustrative. The product will render configured Brando
preview targets using the site's real templates, without saving the proposal.
See the scope document for staged-reference, authorization and cache boundaries.

Source files: `index.html`, `styles.css`, `app.js`, `page-preview.css`,
`page-preview.js`, and `media/`.
Rebuild the offline file after edits with:

```sh
python3 docs/admin-ui/content-agent-concepts/make_standalone.py
```

The concept has no build dependencies. A static server can optionally serve the
source files for development, but no server is required for `concepts.html`.
Brando's application assets and backend are unchanged by these mockups.

## Screenshots

| Option | Desktop | Mobile |
| --- | --- | --- |
| Workspace | [1440px](workspace-desktop.png) | [390px](workspace-mobile.png) |
| Workspace · page preview | [1440px](workspace-page-preview-desktop.png) | [390px](workspace-page-preview-mobile.png) |
| Visual board | [1440px](board-desktop.png) | [390px](board-mobile.png) |
| Guided review | [1440px](guided-desktop.png) | [390px](guided-mobile.png) |

Browser checks cover concept switching, media/detail dialogs, Escape dismissal,
simulated confirmation/receipt, review gating, before/after placement, adjustment
submission, page-preview entry/version/viewport/highlight controls, batch
confirmation from a single-page preview and horizontal overflow at 1440px and
390px. These checks validate the
prototype only, not the proposed backend feature.

## Illustrative media

The photos and graphic treatments are placeholders, not actual Sommerro project
assets. `identity.svg`, `film.svg` and `palette.svg` are original artwork created
for this concept. The fonts come from Brando's E2E consumer.

Downloaded sample photography:

- `hotel.jpg`: [Unsplash photograph](https://images.unsplash.com/photo-1566073771259-6a8506099945).
- `room.jpg`: [Unsplash photograph](https://images.unsplash.com/photo-1611892440504-42a792e24d32).
- `architecture.jpg`: [Unsplash photograph](https://images.unsplash.com/photo-1511818966892-d7d671e672a2).

The implementation plan requires **in-process MCP execution with no MCP URL,
route, port, listener or tunnel**, in development and production. This constraint
is independent of the eventual interface choice.
