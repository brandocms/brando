# Connected AI tools (remote MCP)

Brando can let people connect Claude, ChatGPT, Claude Code, VS Code and other
[MCP](https://modelcontextprotocol.io) clients to a site. A connected tool
reads content and prepares proposals, as the person who connected it; the
person reviews and applies the proposals in the Assistant, under **From
connected tools**. Nothing a tool does publishes or deletes content, and
nothing it proposes is saved without review, except unpublished translations
on a connection a site's managers allow to create them
([Apply translations without review](#apply-translations-without-review)).
With Figma connected, a tool can also read a Figma frame and import its
images into the media library, to build an entry from a design (see
[Build from Figma](#build-from-figma)).

The endpoint is off until an administrator turns it on, per site and
environment, and only people with the **Connected AI tools → Connect**
permission and two-factor authentication can connect. It is the only network
path to MCP in Brando: BrandoMCP's own transport is stdio, for development
(`mix brando.mcp`).

<!-- usage-rules:start topic="assistant-mcp" -->

## Enable the endpoint

1. Mount the routes in the application's router, after `admin_routes` and
   before the scope that calls `page_routes()`:

   ```elixir
   admin_routes do
     # …
   end

   mcp_routes()

   scope "/" do
     pipe_through :browser
     page_routes()
   end
   ```

   `mcp_routes/0` mounts `/mcp`, `/mcp/*`, two
   `/.well-known/oauth-…/mcp…` metadata paths and the consent screen at
   `/admin/mcp/authorize`. Run `mix brando.gen.migrations` and
   `mix brando.migrate` for `brando_213`, which creates its tables in
   `public`.

   Optionally, plug `Brando.MCP.BodyLimit` into the endpoint just before
   `Plug.Parsers`. The endpoint's parser reads a request body before the
   router sees it (up to its own `:length`, often several megabytes); the
   plug refuses a POST to `/mcp` with a `Transfer-Encoding` (400), without a
   `Content-Length` (411) or over `max_request_bytes` (413) before anything
   reads it:

   ```elixir
   plug Brando.MCP.BodyLimit

   plug Plug.Parsers,
     parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
     pass: ["*/*"],
     json_decoder: Phoenix.json_library()
   ```

   Without it, the MCP endpoint applies the same limit from the same header
   itself, before it looks at the token, but after the parser has run.

   The plug also refuses a PUT to an upload URL (below) sent as JSON or a
   form (415), so the parser never reads it. An upload's bytes pass the plug
   and the parser untouched; the upload URL itself reads them and holds them
   to the image config's size limit.

2. Make sure the endpoint's URL (`config :my_app, MyAppWeb.Endpoint, url:
   […]`) is the public `https` address. The MCP URL, the OAuth issuer and the
   token audience are all made from it, and production refuses to turn the
   endpoint on over plain `http`.

3. In the admin, go to **Configuration → Integrations → Connected AI tools**
   and choose **Turn on**. The screen shows the server URL to give people:

   - without tenancy: `https://example.com/mcp`
   - with tenancy: `https://example.com/mcp/<site>/<environment>`, one per
     site environment, each turned on by itself.

   **Turn off** is a kill switch: it disconnects every connected app of the
   site environment at once (the confirmation says how many), and people
   connect them again once it is back on. While it is off, the endpoint, its
   sign-in and its metadata answer 404 as a missing route does (see
   requirement 1 below).

<!-- usage-rules:end -->

Turning it on or off needs **Connected AI tools → Manage** (the admin and
superuser roles without group authorization). Configuration → Integrations
opens for people who may manage webhooks or connected AI tools, and shows each
of those rows only to those who may manage it. Turning it on or off asks for the password or a code
when the session has not given one lately, and is recorded in Activity.

<!-- usage-rules:start topic="assistant-mcp" -->

## Let someone connect

- With group authorization, grant **Connected AI tools → Connect**
  (`brando.mcp.connect`) to a group. No preset includes it, and the Content
  assistant permission does not imply it.
- **Connect lets a person propose; reviewing takes the Assistant.** A tool
  connected by someone with only Connect can read content and prepare
  proposals, but the proposals are reviewed, applied or discarded in the
  Assistant, under **From connected tools**, which takes **Content
  assistant → Use**. Give people who connect tools both, or someone else
  cannot see what they proposed.
- Without group authorization, people with the admin or superuser role can
  connect (for a site, their role on that site).
- The person needs two-factor authentication (an authenticator app or a
  passkey) under **Security**.

Both are checked again on every request, not only when connecting.

<!-- usage-rules:end -->

## Connect a tool

Each person connects with their own account. The tool opens Brando's sign-in
in the browser; after the password and the second step, the consent screen
names the tool, the host that publishes its name, where it sends the person
back to and the site environment, and asks for the password or a code again
when the session has not given one in the last ten minutes. **Allow** connects
it; **Cancel** tells the tool no.

**Claude (claude.ai, Desktop and mobile).** In Claude, open **Settings →
Connectors**, choose **Add custom connector**, give it a name and paste the
server URL. Leave the OAuth client fields empty: Claude identifies itself
with its own client metadata document. Choose **Connect** and sign in to
Brando. Organisation owners add the connector for the organisation first, and
members connect it from the same place.

**Claude Code.**

```sh
claude mcp add --transport http brando https://example.com/mcp
```

Then run `/mcp` in Claude Code, choose `brando` and **Authenticate**: Claude
Code opens the browser and listens on a local port for the answer, which the
consent screen shows as "A program on this computer".

**ChatGPT.** Turn on developer mode in ChatGPT's settings, add an app
(connector) with the server URL, and choose OAuth as its authentication.
ChatGPT finds Brando's sign-in from the URL. ChatGPT renames these menus
often; OpenAI's documentation on connecting remote MCP servers has the
current steps.

**VS Code.** Add the server to `.vscode/mcp.json` (or with **MCP: Add
Server… → HTTP**), then start it and allow the sign-in:

```json
{ "servers": { "brando": { "type": "http", "url": "https://example.com/mcp" } } }
```

Other clients need Streamable HTTP and OAuth with Client ID Metadata Documents
(below). A client that only supports dynamic client registration cannot
connect.

## What a tool can do

The tools are the Assistant's own (`Brando.Content.Proposals.Tools`), named
`brando_content_…` as in BrandoMCP: `list_content_types`,
`describe_content_type`, `search_entries`, `entry_outline`,
`translation_work`, `list_modules`, `describe_module`, `list_entry_media`,
`list_selection_options`, `search_assets`, `find_media_folders` and
`prepare_proposal`. The tools that
work with an Assistant conversation's attachments (`list_attachments`,
`attach_folder`, `request_media`, `look_at_media`) are left out. A tool added
to the registry later is not offered here until it is added to
`Brando.MCP.Tools`.

Every call runs as the person, with their permissions in the site
environment the connection belongs to. A proposal only creates and changes
the content types `list_content_types` lists. A palette can be found, read
and picked, but not created or changed; Brando's own records (users, global
sets, menus, vars, modules, site settings) are refused too, and the tool gets
an error. Results are bounded as in the Assistant: 20 results, 160-character
excerpts (a text is whole when `entry_outline` reads one block), 24 KB per
result; `translation_work` returns a long entry's work in batches instead. Proposals
are marked with the tool's name, "From Claude via MCP", and wait under
**Assistant → From connected tools**. `prepare_proposal` answers with
`review_url`, the proposal's review there, and, when an entry the proposal
creates or changes has a page preview, `preview_url`: the review opened on
the first such entry's page (`?preview=<entry key>`), which is the link to
give the person. A proposal can create a synchronized entry's version in
another language with `create_translation`, as the admin's **Create
translation** does ([Language versions](content_assistant.md#language-versions)),
and translate a synchronized version with `translate`, answering each batch
`translation_work` read; both in one proposal create the version and fill it in
([Translating with a proposal](content_assistant.md#translating-with-a-proposal)).
`sync_translation` saves a synchronized translation's pending version as it
is, taking the links, media and source-controlled values its source changed
(`translation_work`'s `other` items), while its texts stay to translate
([Taking the source's changes](content_assistant.md#taking-the-sources-changes)).
On a synchronized translation, `translate` and `sync_translation` are the only
operations besides a `set_fields` on the fields that are its language's own,
such as its status or slug; the others are refused, with a problem that says
to change the source or to use `translate`
([Language versions](content_assistant.md#language-versions)).

With them, three tools that add images to the media library (below):
`brando_media_prepare_upload`, `brando_media_finish_upload` and
`brando_media_import_url`. With Figma connected, two more:
`brando_figma_read_frame` and `brando_figma_import_images`; and
`brando_figma_status`, which checks how the site reaches Figma
([Connect Figma](#connect-figma)).

### Follow up on proposals

Three content tools are offered only to connected tools, not to the
Assistant, so a tool can check on its proposals and see their pages instead
of asking the person:

- `brando_content_list_proposals` lists the tool's own proposals, newest
  first, in every status: pending, approved, applied, undone, superseded
  and cancelled. Each has its `proposal_id`, `version`, `summary` (cut to
  300 characters, with `summary_cut: true`, when longer), `status`,
  `changed_at` (when its status or its problems last changed), `expires_at`,
  `expired: true` when a pending or approved one can no longer be
  approved, and the entries it changes (`content_type` and `id`) and
  creates (`content_type` and the proposal's `ref`, with the saved entry's
  `id` once it is applied). A proposal that replaces an image's file names
  that image in `replaced_images` (`kind`, `id`, and the image whose file
  it takes, `with`), not in the entries, and does not list the entries
  that use the image. A superseded one names the version that
  replaced it as `superseded_by`. `changed_by` is `"person"` for an
  approved, applied or undone proposal, since only the person can do those,
  and `"connection"` for one applied without review; such a proposal has
  `applied_automatically: true`, undone or not. Who stored a version or
  cancelled a proposal is not kept. It filters by
  `status` and `proposal_id`, and gives 20 proposals, or up to 50 with
  `limit`. It changes nothing.
- `brando_content_cancel_proposal` cancels one of the tool's own proposals
  while it is pending or approved, expired or not, as **Cancel** in the
  admin does: content is untouched. An applied, undone, superseded or
  cancelled proposal is refused with an error that names its status.
- `brando_content_preview_proposal` returns `url`, a link to one entry's
  page as one of the tool's own proposals would make it, before anyone
  approves it, so the tool can compare the page with its design (a Figma
  frame) and refine the proposal. It takes `proposal_id`, `target` (an
  entry the proposal changes, `{"content_type", "id"}`, or creates,
  `{"new": ref}`), `version` (`"proposed"`, the default, or `"before"`:
  the entry as it is saved now, which a new entry does not have) and
  `preview_target` (one of the content type's views; its default view
  otherwise). The page is rendered by the site's own templates against the
  site's frontend assets and stored as a snapshot, as the editor's **Get
  shareable link** stores one; nothing else is saved.

### Apply translations without review

A connection can be let to apply, without review, proposals that only create
unpublished translations. It starts set to review everything, and so does a
new connection from the same tool. Under **Configuration → Integrations →
Connected AI tools**, someone who manages connected tools sets it per
connection in the **Without review** column: **Allow translations**, and
**Review everything** to take it back, each asking for the password, a code
or a passkey when the session has not given one lately. The column says who
set it and when; the connection's person sees it under **Security →
Connected apps**, and the consent screen says the site's managers may allow
it. Each change is written to Activity.

The tool asks for it with `apply: "if_allowed"` in `prepare_proposal`. The
proposal is stored as any proposal is, and then applied as the person, with
their permissions at that moment, as an approval in the admin applies it
(locks, staleness checks, validation, Activity), when all of these hold:

- the connection that authenticated the call is set to allow it, still
  valid, its endpoint on, its site active, and its person still allowed to
  connect, checked under a lock on the endpoint's switch and the
  connection, so turning the setting off, revoking the connection or
  turning the endpoint off first applies nothing, and doing it while the
  apply runs waits for the apply;
- the person may review proposals (**Assistant → Use**);
- every operation is a `create_translation`, or a `translate` of
  `{"new": ref}` that a `create_translation` in the same proposal creates,
  read from the stored proposal;
- every entry it created is a draft with no publication date ahead once all
  operations have run. A content type without a status never qualifies.

Applied, the result has `applied: true`, `status: "applied"` and `created`
(each ref's new entry id), with no `review_url`. Otherwise nothing of the
attempt is kept: the proposal waits for review, unapproved, and the result
has `applied: false` and `not_applied`, a sentence saying why. When the
person cancelled or applied the proposal in the admin while it was being
tried, the result says so, with its `status` and no `review_url`. Why a
proposal waits is kept with it: `list_proposals` returns it as
`not_applied`, and its review page shows it. A waiting
proposal does not count as one with problems, so the tool's next proposal
does not replace it. The Assistant and the local development server never
apply a proposal so.

A proposal applied so is marked **Applied automatically** in the list under
**Assistant → From connected tools** and on the connection's live page, and
Activity says "Applied automatically as" the person instead of "Approved
by". It is undone as any applied proposal is. Proposals that wait are always
listed there, however many were applied since.

### Proposal preview links

A link from `preview_proposal` opens in any browser without a login, for
15 minutes (`expires_at` in the answer), and only while its proposal is
pending or approved: once the proposal is applied, replaced, cancelled,
undone or past its own expiry, the link answers 404. Approving it keeps the
link. Each call gives a new link; an earlier one keeps working until its
own 15 minutes are up, so two views of one entry can be compared side by
side. A proposal that is no longer under review, or has problems, gets no
link; its `before` version is still shown while it has problems.

The tool gets a link only when the person could see the same page in the
admin's own review: it is the person's proposal from this tool, and the
person may edit the entry, both as it is and as the proposal leaves it (for
a new entry, may create it). The export permission the editor's shareable
link takes is not needed. A translation the proposal creates has no page of
its own until it is applied: preview its source.

In multi-site mode the link opens only under the site environment the
proposal belongs to: on the admin's host and on that environment's own
host, not on the same site's live host for a staging proposal, and nowhere
once that environment is deleted. The page is served with
`X-Robots-Tag: noindex, nofollow` and `Cache-Control: no-store`, and without
a banner, so a screenshot of it is the page. Expired snapshots are removed
as other shared previews are. The live page and Activity record each call
with the proposal and the version it showed, not the link.

A proposal stores the person and the client's name, not the connection, so
a tool's own proposals are those the same person made over MCP from a
client with the same name, in the same site environment. They stay the
tool's after it is reconnected, and two connections of the same client for
the same person share them. A proposal without a client name belongs to a
tool that sends none. Another person's proposal, another client's, an
Assistant conversation's and one from another site environment are not
listed, and cancelling or previewing one answers that there is no such
proposal.

### The site's guidance

A connected tool gets the same site guidance as the Assistant, through the
tools' results rather than the server's instructions, which some clients
ignore. The instructions `initialize` and `server/discover` give only say
where it is.

- `brando_content_describe_content_type` returns the guidance for that
  content type under `guidance`: the administrators' (**Configuration →
  Assistant guidance**) and the developers' baseline for the content type
  (`config :brando, Brando.AI.Agent, guidance:`), with a line on how to use
  them. Both together are limited to 12,000 characters, and cut further when
  the result would go over 24 KB; either way the developers' part is cut
  first, since the administrators' applies where they conflict. A content
  type the person may not read is refused as before, guidance and all.
- It also describes each field with its label and instructions from the
  content type's admin form ("Introduction — Used for case listings"), so a
  tool can tell that a heading or an introduction belongs in the entry's own
  field rather than in a text block. The Assistant reads the same
  descriptions. Write instructions that say where a field shows.
- `brando_figma_read_frame` returns the guidance for building from Figma
  (below).

Guidance informs the tool and nothing more: every call is still authorized
as the person, and every proposal checked and reviewed in the admin.

Every call is written to Activity: the person, the tool's name, the tool it
called, whether it worked and the id of the token's database row (never the
token), with what the live page shows of it (below). People who manage
connected tools see these under **Configuration → Activity**.

### Follow a tool as it works

Each connection has a live page in the admin,
`/admin/assistant/connected/live/<connection>`, that shows what the tool does
on the site while it works: each call as it starts and as it ends, with what
it was about ("Searched for “harbour” in Pages", "Read the Figma frame
“Home”"), whether it worked and the error if not; the images
an upload, an import from an address or `brando_figma_import_images` adds or
reuses, with their thumbnails and library folder; and each proposal `prepare_proposal` stores or `cancel_proposal` cancels, with its
summary, counts, problems and links to its review and page preview; a
`preview_proposal` call says which version it showed, without its link. It opens
on the connection's calls of the last hour (at most 50) from Activity, then
follows the new ones; it changes nothing, and cannot steer the tool.

The connection's person, while their account is active and may enter its
site, and those who manage connected tools in its site environment can open
it, behind the admin sign-in; anyone else gets the access-denied page,
whatever the link. A page already open is checked again whenever
permissions change, and one that may no longer be seen leaves for the
access-denied page. **Follow live** opens it from
**Security → Connected apps**, from the connections under
**Configuration → Integrations → Connected AI tools**, and, for the
person, from each proposal under **Assistant → From connected tools**,
which links the newest connection of the tool that prepared it. A revoked or expired
connection's page says it has ended and shows what it did, and an open page
says so the moment it expires.

The person sees everything on it. Someone who manages connected tools sees
another person's calls as Activity shows them: each call's line without
what it named (an entry's title, the words searched for, the Figma frame,
an upload's file name and the library folder), only the images they may read, and a proposal's
summary and problems only when they may read every entry it changes;
otherwise just its version, state and counts, without the review links,
which only the person opens.

The link lasts as long as the connection, and the tool gets it right away:

- the instructions `initialize` and `server/discover` give end with it, for
  the tool to give the person before it starts;
- `prepare_proposal` returns it as `watch_url`, next to `review_url`;
- the first result after 30 minutes without calls returns it as
  `watch_url` too, for clients that do not show the server's instructions.
  Each server node remembers the connection's last call in memory, so
  another node may give the link once more, and a result at the 24 KB limit
  goes without it.

To keep the page useful, Activity keeps a short summary of each call beside
it: the few arguments its line names (a search's words, a content type, a
module), cut to 120 characters, the part of the result that names its
subject (an entry's title, a frame's name, a proposal's version), the error
cut to 300 characters, the ids of the images an import or upload added or
reused and their folder, and the proposal's id. Never a whole argument or
result: not an upload URL, and not the address an image was imported from.

## Add images

A tool can add an image to the media library, from a file it has or from a
public address, and use it in a proposal: a better copy of a photo, an image
the person hands it, or one on another website.

- `brando_media_prepare_upload` takes `kind` (`"image"`; files and videos
  are refused for now, with a message that says so), the file's `filename`
  and optionally a library `folder` (a path such as
  `products/2026`, as `brando_content_find_media_folders` gives it, or a new
  one; `uploads` without it). It answers with an `upload_url`, an
  `upload_id`, when the URL expires, the most bytes it takes and the image
  types the site takes.
- The tool sends the file's bytes to the URL with a PUT:
  `curl -T photo.jpg '<upload_url>'`. The URL is the only credential that
  needs, and it works once: a second PUT, even after a failed one, is
  refused, and the tool prepares a new upload. `Brando.Plug.RequestLog`
  logs it with the secret filtered out, and its route logs no parameters
  (Phoenix's debug line would show the path's segments).
- `brando_media_finish_upload` takes the `upload_id` and stores the image
  as an editor's upload is stored (`Brando.Uploads.store_upload/4`), under
  the default image config: its types, size limit and pixel limit, its sizes
  made in the background. It answers with the image's asset,
  `{"kind": "image", "id": N}`, for `prepare_proposal`.
- `brando_media_import_url` takes an `https` `url`, and optionally a
  `filename` (the last part of the address's path without it) and a
  `folder`, downloads the image and stores it the same way, with the same
  answer.

Both store an image the library already has, the same bytes for the same
config, only once: the answer says `"reused": true` and gives the image the
library has. The type comes from the file's bytes, not from its name or the
request's `Content-Type`, and names the stored file's extension. A new
`folder` is made when a new image is about to be stored in it: not for an
address or download that is refused, nor for an image the library already
has. An image the store itself refuses (over the pixel limit, an SVG it
does not take) can leave the folder, empty.

`brando_media_finish_upload` and `brando_media_import_url` also take:

- `focal`, the image's focal point, either as `Brando.Images.Focal` stores
  it, `{"x": 0–100, "y": 0–100, "mode": "center" | "position"}` (percent
  from the top left; without `mode`, `center`), or
  `{"from": {"kind": "image", "id": N}}`, which copies image N's focal
  point. A better copy of the same photo keeps its framing that way.
- `title` and `alt`, the image's caption and alt text, in the site's
  default language.

They are checked before anything is stored, and set on a new image; one the
library already had keeps its own, an editor may have set them. The answer
lists what was `applied` and `not_applied`.

The images are added when the tool adds them, before anyone applies a
proposal, and stay in the library if the proposal is discarded. Adding them
needs permission to create images, checked when the upload is prepared,
again when its bytes arrive (with the connection, which must still be good),
and again when it is finished. Every call shows on the connection's live
page and in Activity with the image it added or reused.

An upload URL is bound to the connection that prepared it and to its site
environment: another connection, even the same person's, cannot finish the
upload, and the URL answers only at the endpoint it was made for. It expires
10 minutes after it is prepared; the bytes must have all arrived 10 minutes
after the PUT starts, and the upload must be finished within the hour.
A connection has at most 10 uploads waiting at once; one whose bytes were
refused, whose URL expired with nothing sent, or whose PUT stopped without
an answer and is past its 10 minutes, does not count, and finishing it says
it failed. A request whose
`Content-Length` is over the image config's size limit is refused before a
byte is read, and one sent without a length is cut off the moment it passes
the limit; one whose first bytes are not an image type the config takes is
cut off there.

Uploads wait in the application's own directory,
`brando-mcp-uploads-<otp_app>`, which Brando makes in the system's temporary
directory, or in `upload_dir` (below) when it is set, readable by the server
only, until they are finished. The directory around it is left as it is, and
a directory of that name Brando cannot make its own (a link, or another
user's) is refused: nothing in it is listed, read, written or removed, by
the nightly purge either, and the log says once why every upload is refused.
One not finished in time is removed when the connection's next
upload is prepared and by the nightly purge. With more than one server
node, set `upload_dir` to a directory every node shares.

An import from an address goes through the webhooks' address guard, as the
Figma import does: `https` only, public addresses only (checked on every
address the host resolves to, and connected to the address checked), no user
name or password in the address, no redirects, at most the image config's
size limit, within a minute.

### Replace an image's file

To put a better copy of a photo in place of the one the site has, a tool
uploads it (above) and proposes the `replace_image_file` operation:

```json
{"op": "replace_image_file", "asset": {"kind": "image", "id": 12}, "with": {"kind": "image", "id": 87}}
```

On approval, image 12 (OLD) takes the file of image 87 (NEW): its path,
dimensions, type, formats and `content_hash`. It keeps its id, focal point,
title, alt text, credits, folder, image config and every place it is used,
so every entry that shows it shows the new file. Its sizes are made again
in the background, as for an upload; until they are, OLD shows NEW's sizes,
and a size of its own config that NEW lacks is missing. NEW's record is
removed, since its file is now OLD's. The other way to replace an image, which keeps OLD in the
library and reviews each use, is to swap the references: `set_block_media`
and `set_fields` to NEW.

When the proposal is prepared, and again when it is approved and applied:

- Both are images the person may read, in this site environment, and
  neither is in the trash. They are not the same image, nor the same file.
- NEW's file is one OLD's image config takes, by type and size limit, and
  is an SVG only when OLD's is: an SVG has no sizes, and OLD's crops and
  focal point carry over.
- NEW's image config delivers through the same CDN as OLD's, or neither
  through one: OLD reads and links the file through its own config. An
  image config can have a CDN of its own per field.
- Nothing uses NEW yet: no entry, in the trash or not, no gallery, variable,
  recovery draft or module default, and no other operation of the proposal.
  Otherwise the proposal says so and points to swapping the references.
- The person may update both images and every entry that shows OLD, in the
  trash too, since restoring it shows the new file. The problem names the
  entries they may read and counts the others.
- Neither image has another file than when the proposal was prepared: of two
  proposals replacing the same image, the second is refused once the first
  is applied.

An approval while NEW's own sizes are still being made (just after the
upload, with image processing busy) is refused, to be tried again in a
moment; the proposal stays as it is.

The review, under **Assistant → From connected tools**, shows the two files
side by side with their dimensions, the entries that show OLD, linked, and
a warning when the proportions differ, since the focal point and crops carry
over unchanged. Applying it changes the two images' rows in the proposal's
transaction and moves no file, so an approval that fails anywhere leaves
OLD as it was, with its files. What happens to OLD's previous files is in
[Replacing an asset's bytes](media.md). A proposal that replaced an image's
file has no undo.

The proposal's line on the connection's live page says how many files it
replaces, and Activity records the replacement on the image, with the
proposal and the person who applied it. The entries that show the image are
rendered again once its new sizes are made.

## Build from Figma

A tool can rebuild a Figma frame as an entry: the person gives it the
frame's link (in Figma, select the frame and copy its link, which has
`?node-id=…`), and it reads the frame, imports its images and prepares a
proposal with the modules that match.

- `brando_figma_read_frame` lists the frame's sections in reading order. A
  section is an outermost component instance, with its component (and
  variant) name, its texts, its images and its videos; a text, image or
  video outside every instance is a section of its own. Hidden layers are
  left out. The component names are what the tool matches to modules, so
  frames built from components named like the site's modules ("Case/Image
  full" for a module named "Case image full") rebuild most faithfully.

  Each section, text, image and video has its layer box in the frame (`x`,
  `y`, `width` and `height`, in Figma pixels from the frame's top left), and
  the frame has its size and its visible layout grids (`layout_grids`:
  pattern, count, gutter, margin, alignment and column size), so the tool
  can tell which images share a row, how many columns come before one and
  how far it drops below its neighbour. The box is the layer's own, before
  clipping and masks: an image cropped by its frame or a mask can reach
  past the cell it shows in.

  Each image has the `image_ref` of the picture it shows. It identifies the
  picture: layers with the same `image_ref` show the same picture, and
  `brando_figma_import_images` imports it once.

  An image whose picture `brando_figma_import_images` has imported, or
  reused a library image for, has its `asset` (`{"kind": "image", "id":
  N}`): the media library image that import gave it, for the image's
  rotation (a picture shown turned a quarter is a turned copy of its own).
  It is one the person may read and that is not in the trash, the oldest
  when there are several, as the import reuses the oldest. Reading it costs
  no download and no call to Figma. An image without an `asset` has no
  library image recorded for its picture and rotation that the person may
  read and is not in the trash; the library may still have the picture,
  uploaded some other way, and the import finds it by its contents.

  Each image has its `scale_mode` (`fill`, `fit`, `crop` or `tile`), its
  `crop` when cropped (`x`, `y`, `width`, `height` as fractions of the
  image), its `rotation` when turned (clockwise, in degrees) and
  `mirrored` when a crop flips it (it then has no `rotation`). A layer
  with several image fills, as when a designer swaps a photo by adding one
  on top, is one image when its top fill covers it: opaque, unblended, and
  filled, or cropped so the image reaches every corner of the layer. A
  layer whose top fill is translucent, blended, fit, tiled or cropped short
  of an edge lists every image that shows, and its section says so in
  `note`. The image fills that do not show, under one that covers or at no
  opacity, are listed as the bottom image's `hidden_fills` and are not
  imported. They are often leftovers of an earlier design, so they say
  nothing about the picture the layer shows.

  Figma's API documents no direction for the `rotation` of a filled, fit
  or tiled image. It is read as clockwise, as Figma's Rotate 90° control
  turns, and as OpenPencil and Octopus draw it; no render by Figma has
  confirmed it.

  A section named like the page's header, footer or menu is marked
  `chrome`, with the reason: `"name"` (its layer name) or `"component"`
  (its component's name). The last part of the name, after any slashes,
  has to be header, footer, nav, navbar, navigation, navigasjon, topptekst
  or bunntekst as a whole word, or joined to "hoved" and the like ("Site
  header", "Main navigation", "NavBar", "Header v2", "Hovednavigasjon"; not
  "Section header", "Subheader" or "Navn"). The parts before it must be a
  library's grouping such as Site, Global, Layout or Components
  ("Global/Footer"); under a module's name ("Case/Header") it is content.
  Menu, meny, topp and bunn ("Hovedmeny") count only on a short bar across
  most of the frame, flush with its top or bottom edge, since a module can
  be a restaurant's menu or a page's opening section. Only component
  instances are matched, not text layers,
  which Figma names after their text, and not variant values such as
  `Color=Navy`. A section with images but no texts is never marked, nor is
  the frame itself or a frame's only section. The mark is a hint: the
  section is still listed, and the tool checks its texts before leaving it
  out of the entry.
- `brando_figma_import_images` imports the frame's image fills, the originals
  placed in Figma rather than renders, into the library folder
  `figma/<frame name as a slug>` under the default image config's upload path, and
  answers with each image's asset for the proposal and the layers that show
  it. An image the library
  already has (the same file, for the same config) is reused, so importing a
  frame twice adds nothing. An image shown turned 90, 180 or 270° is
  imported as a turned copy; other angles, a mirrored crop and the turn of
  an animated GIF or WebP (which would keep one frame) are not applied. A
  cropped image keeps its whole file, and a new one gets its focal point set
  so the site shows the crop Figma shows, and the sizes Brando cuts and the
  share cards follow it too. A crop that spans the image's whole width or
  height shows exactly in a box of the layer's proportions; one that zooms in on both shows with more of the
  image around it. One the library already has keeps its own focal
  point, and when several layers show one image, the first layer's crop
  sets it. Each answer says what was applied and what was not, naming the
  layer when only one of several missed it. It imports at most eight images per call; the
  tool calls again for the rest. The images are added when the tool imports
  them, before anyone applies the proposal, and stay in the library if the
  proposal is discarded. Importing needs permission to upload images.
- An image over the default image config's size limit is not imported: its
  entry names the image, the limit, its size when Figma's answer gives it,
  and what to do. The other images of the call are imported. Called with
  `fit: true`, the tool imports a copy of such an image scaled down on the
  server, the size limit unchanged: as large as fits under the limit, never
  enlarged, and never smaller than twice the image's largest use in the frame
  (for a crop, what the whole image needs for the part shown to be twice the
  layer), counting the layers outside `node_ids` too. A picture that does
  not fit in its own format at that size is stored as a JPEG, or as a WebP
  when it has transparent pixels, if the image config takes that type; one
  still over the limit, an animated GIF or WebP and one over the pixel limit
  are refused with the reason. A copy turned as Figma shows it that comes
  out over the limit is scaled down the same way. The entry says the image was fitted, with its original and
  stored pixel sizes. `fit` leaves the images within the limit as they are.
  It downloads an image up to 50 MB (or the size limit, when that is larger)
  to scale it down; a site sets another cap with
  `config :brando, Brando.Figma, fit_download_limit: 80_000_000`.
- Figma's API cannot download videos. Upload them to the media library
  yourself, named so the tool can tell where each goes (after the Figma
  layer, for instance), and tell the tool the folder: it finds them with
  `brando_content_find_media_folders`.

### Guidance for building from Figma

Rebuilding a design takes conventions of its own, which the Assistant does
not need: how the design's frames and components map to the site's modules
when they are not named after them, which texts are the entry's own fields,
and what to leave out. For example:

- "The frame's top text is `heading` and `intro`; the mono credits at the
  bottom are `credits`."
- "The listing image (`cover_id`) is not in the project frame; it is on the
  projects overview frame."
- "Header and footer are page chrome: leave them out."
- "Videos uploaded by hand are in the folder Projects/Videos."

Write it under **Configuration → Integrations → Connected AI tools →
Figma**, below the connection and the token. Every save is a version, as with the Assistant's
guidance, and an earlier one can be loaded into the editor. Editing it takes
the same right as the Assistant's guidance (**Content assistant →
configure**, superusers by default); others who manage connected tools see
it read-only. Developers can ship a baseline:

```elixir
config :brando, Brando.Figma,
  guidance: MyApp.FigmaGuidance
```

A string, or a module implementing `Brando.AI.Agent.Guidance`, called with
the site and environment keys and `content_type: nil`. The screen shows it
read-only, and where the two conflict, the administrators' applies.

`brando_figma_read_frame` returns both under `guidance` on the frame's first
page (`offset` 0), within 12,000 characters. To make room, that page leaves
its last sections to the next one; guidance never shortens a section. When
the first section alone leaves too little room, the guidance is cut, the
developers' part first. The Assistant's prompt never includes it.

### Connect Figma

The tools reach Figma in one of two ways per site environment, both under
**Configuration → Integrations → Connected AI tools → Figma**, which takes
the same **Connected AI tools → Manage** permission as the switch:

- through the environment's own **Figma app**, connected with OAuth: its
  access renews itself, so nobody pastes tokens again;
- with a pasted **personal access token** ([Add the token](#add-the-token)),
  which expires after at most 90 days.

An environment with a connected app uses it; one without uses the token, if
there is one. The screen says which one calls use. An app saved but not yet
connected changes nothing: calls keep using the token until Figma is
connected.

Each site environment registers an app of its own in Figma: production,
staging and development each have their own client ID, secret and redirect
URL. Figma keeps one access token per app and Figma account, and renewing it
ends the one before, so two environments sharing an app and an account would
cut each other's access off whenever one renews it. Brando does not enforce
this.

To connect an environment:

1. In Figma, create an app under
   [figma.com/developers/apps](https://www.figma.com/developers/apps), and
   give it the **redirect URL** the screen shows: the admin's callback,
   `<the site's URL><admin path>/config/mcp/figma/callback`, on the
   endpoint's configured URL (the admin host with multi-site tenancy) and
   under the path the admin is mounted at. In single-site mode and without
   tenancy, use the admin on the endpoint's configured host when you
   connect: the redirect URL is built from that host, and a callback that
   arrives on another host does not find your session. Give it two scopes:
   **File content: read** (`file_content:read`), which the tools read frames
   and images with, and **Current user: read** (`current_user:read`), which
   connecting and checking need, to read the account's handle. A private app
   (tied to your Figma team or organization) needs no review by Figma; an
   app still in draft cannot be used by anyone but its owner.
2. Paste the app's client ID and secret under **Connect Figma** and save
   them.
3. Press **Connect**. Brando asks for the password, a code or a passkey
   when the session has not given one lately, before leaving for Figma,
   where the person signs in and allows access. Figma sends the browser back
   to the redirect URL, and the screen says whether Figma is connected.

The calls see the Figma files the account that connected can open, and
Figma's limits on API calls follow that account's seat, as with a token.

Brando asks Figma with PKCE (`S256`) and a random `state`, which lasts ten
minutes, is used once, and belongs to the person and the session that pressed
**Connect** and to the environment they connected. The callback saves
nothing, and says so, when the attempt is unknown or used already, took
longer than ten minutes, came back to another session, when the person may no
longer manage the settings, or when the app or the connection changed while
they were at Figma. When Figma's code cannot be exchanged, or the account it
gives cannot be read, nothing is saved either, and a new attempt starts from
scratch. Figma sends nothing back when consent is refused; a later attempt
replaces the abandoned one.

The app's client ID and secret, the access token and the refresh token are
stored encrypted with `Brando.Crypto`, each bound to its environment, never
shown again and never logged; the screen shows the client ID's last four
characters, the Figma account's handle, and who connected it and when.

Each request to Figma reads the access token, so an import that makes several
requests uses a token renewed between them. Within five minutes of its expiry
the token is renewed first, under a lock on the environment's settings row,
so that calls at the same time renew it once and use the new one; a call
waits a few seconds at most for that lock, then answers that it should try
again in a moment. When Figma answers that a token has expired, it is renewed
once and the request made again. When Figma does not answer a renewal (a
timeout, its call limit, an error at Figma), nothing changes and a later call
tries again. A renewal ahead of the expiry that fails so, or that cannot get
the lock in time, goes on with the stored token while it has not expired. When Figma refuses the renewal, as after the access was revoked
in Figma, the connection is marked **Needs reconnecting**, recorded in
Activity, and the tools answer that an administrator reconnects Figma; they do
not move over to a pasted token meanwhile. A connection that no longer
decrypts (after a change of the encryption secret) is **Needs repair**, with
the same effect; save the app again if it says so, then reconnect.

**Disconnect** removes the connection and keeps the app, so Figma can be
connected again; calls then use the pasted token again, if there is one, as
the confirmation says. **Change app** opens the app's form: another client ID
removes the connection, and Figma is connected again; the same client ID with
a new secret keeps it, and clears **Needs reconnecting**, so that a secret
corrected after Figma refused it needs no new connection (the next call tries
the renewal again). **Remove app** removes the connection too. Saving or
removing the app, connecting and disconnecting are recorded in Activity, and
ask for the password or a code as the token does.

The expiry date and its warnings belong to a pasted token only: a connected
app renews itself.

### Add the token

Without a connected app, the tools call Figma with one personal access token
per site environment, under **Connected AI tools → Figma → Figma access
token**. Create it
in Figma under **Settings → Security → Personal access tokens**, on the
account of someone who can open the files to import, with two scopes:

- **File content: read** (`file_content:read`), which the tools read frames
  and images with;
- **Current user: read** (`current_user:read`), which checking the token
  needs (below). A token without it still reads files, but cannot be
  checked.

Figma limits how often its API answers by the owner's seat and plan: use the
account of someone with a Full or Dev seat, since other seats get far fewer
calls.

Figma's tokens expire after at most 90 days, and its API does not tell when.
The form asks for the expiry you chose in Figma, 90 days from today unless
changed, and takes today or a later date; leave it empty when you do not know
it. The screen shows the date under the token, and warns from a week before
it and after it. A token saved without a date shows "Expiry not recorded".
Replacing the token replaces its date, and removing it clears it. The date
is only what was typed: a passed date stops no call, since Figma decides.

Once the screen is up, it asks Figma about the token (`GET /v1/me`) without
holding the screen up, and **Test** asks again. It shows one of:

- **Valid**, with the handle of the Figma account the token belongs to;
- **Expired** or **Not valid**, with Figma's own words: replace the token;
- **Not checked**, when the token may not read its account (no
  `current_user:read`; it may still read files), or when Figma could not be
  reached (a timeout, a network error, its call limit, an error at Figma, or
  a refusal without Figma's error text, as from a proxy in front of it),
  which says nothing about the token.

The token is stored encrypted with `Brando.Crypto`, bound to its site
environment, and never shown again: the screen shows its last four
characters, when it was added and by whom. Adding, replacing and removing it
asks for the password or a code when the session has not given one lately,
and is recorded in Activity (without the token). Without a token or a connected
app, the Figma tools answer that an administrator connects Figma or adds a
token. Removing it keeps the images already imported.

When Figma refuses a call, the tool says why: the token has expired, the
token (or the connection) is not valid, it lacks the permission to read files
(`file_content:read`), or the account cannot open the file, with Figma's own
words (at most 200 characters). In a pasted token's last week by its recorded
date, `brando_figma_read_frame` and `brando_figma_import_images` carry a
`token_note` for the tool to pass on. `brando_figma_status` lets a tool check
before it starts: what the tools call Figma with (`credential`: `oauth`,
`token` or `none`), where the connection stands (`oauth`: `not_set_up`,
`app_saved`, `connected`, `needs_reconnect` or `needs_repair`), whether a
token is stored, the credential's state as Figma answers now (`valid`,
`expired`, `invalid`, `no_account_scope`, `unreachable`, `unreadable` when a
token no longer decrypts, `needs_reconnect` or `needs_repair`), the account's
handle, a token's recorded expiry date, and a `message` in words. It never
returns a token, its last four characters, the app's credentials or an email
address. Without any credential it answers so, rather than failing.

## Revoke

- **The person:** **Security → Connected apps** lists their connections
  with the site, when each was made and last used. **Disconnect** ends one.
- **An administrator:** **Configuration → Integrations → Connected AI tools**
  lists everyone's connections to this site environment. **Revoke** ends one.
- **The tool:** the OAuth revocation endpoint (RFC 7009) ends the connection.

A revoked connection's tokens stop working on the next request. Brando
revokes all of a person's connections when:

- their password changes: by them, through a reset link, or set by an
  administrator (the only ways it can change: `Brando.Users.update_user/3`
  refuses a saved user's password);
- they, or an administrator, log them out everywhere ("Log out other
  sessions" on the Security page too);
- two-factor authentication is turned off, reset by an administrator, or
  their last passkey goes;
- the account is deactivated or deleted.

Turning the endpoint off revokes every connection to that site environment.
Taking the Connect permission away stops the next call (a plain 403)
without revoking: the connections work again if the permission comes back.

A connection also expires 90 days after consent (`grant_days`), however
often it is refreshed: its refresh token is refused with `invalid_grant`,
Connected apps marks it as expired, and the person connects the tool again.
The nightly `Brando.Worker.ActivityPurger` removes tokens and codes that
nothing can use any more (`Brando.MCP.prune/0`).

<!-- usage-rules:start topic="assistant-mcp" -->

## Configuration

```elixir
config :brando, Brando.MCP,
  access_token_minutes: 60,
  refresh_token_days: 30,
  grant_days: 90,                 # a connection's lifetime from consent
  requests_per_minute: 60,        # per connection
  user_requests_per_minute: 120,  # per person, over all their connections
  token_requests_per_minute: 30,  # per address, at the token and revocation endpoints
  authorize_per_minute: 30,       # consent screen checks per person
  max_request_bytes: 512_000,
  allowed_origins: [],            # browser origins allowed besides the site's own
  upload_dir: nil,                # uploads wait in a directory Brando makes here; the system's temporary directory by default
  upload_url_minutes: 10,         # an upload URL's life
  upload_transfer_minutes: 10,    # how long one PUT may take
  upload_keep_minutes: 60,        # an upload must be finished within this, from preparing it
  upload_max_pending: 10          # uploads waiting per connection
```

Rate limits count per node, like the sign-in throttle (`Brando.RateLimit`).

<!-- usage-rules:end -->

## How it works

- **Transport.** Streamable HTTP: one JSON-RPC request per POST, answered
  with `application/json`. Both protocol eras are served: `2026-07-28`, where
  every request names its version in `_meta` and the `MCP-Protocol-Version`,
  `Mcp-Method` and `Mcp-Name` headers must match the body, with
  `server/discover`; and `2025-11-25`, `2025-06-18` and `2025-03-26`, with
  `initialize`. No session is kept. GET and DELETE answer 405, batches 400.
- **Discovery.** A request without a token gets 401 with `WWW-Authenticate:
  Bearer resource_metadata="…"`. The protected resource metadata (RFC 9728)
  names the endpoint as its own authorization server, whose metadata
  (RFC 8414) lists the authorize, token and revocation endpoints, S256 PKCE,
  `token_endpoint_auth_methods_supported: ["none"]` and
  `client_id_metadata_document_supported: true`.
- **Clients.** A client's `client_id` is the `https` URL of its metadata
  document (Client ID Metadata Documents, which the MCP specification
  prefers to dynamic registration and which Claude, Claude Code, ChatGPT and
  VS Code use). Brando fetches it only when a signed-in person who may
  connect opens the consent screen, and caches it for five minutes. Clients
  are public: no client secrets.
- **Tokens.** The code flow with PKCE (S256 only) and resource indicators
  (RFC 8707). Codes last a minute and work once. Access tokens last an hour;
  refresh tokens 30 days, and each works once: a refresh returns a new pair.
  Neither outlives the connection's 90 days. Tokens and codes are random and
  stored as SHA-256 hashes.
- **Refreshing twice at once.** A client that sends the same refresh token
  twice within ten seconds, while the pair the first request returned is
  unused, gets that same pair again. The pair is held for those ten seconds
  in the node's cache, encrypted with `Brando.Crypto`, never in the
  database. With several nodes, a second request that lands on another node
  finds nothing there and counts as reuse. Any other second use of a refresh
  token, later or after its successor was used, is treated as theft and
  revokes the whole connection; the person connects the tool again.
- **The consent screen never redirects by itself.** A request that is wrong
  (an unsupported `response_type`, no S256 challenge, an unknown scope, a
  `state` over 1024 bytes) is shown on an error page. Only a click on
  Allow, Cancel, or "Back to …" on that page sends the person to the
  client's redirect URI, and only once the client's document lists it.

## Threat model

**Assets.** Content and media of every site environment, including drafts;
the proposals people review and apply; people's accounts and sessions; the
tokens of connections.

**Actors.** A person with an account and the Connect permission; a tool they
connect (a model working on their behalf, following instructions that may
come from content or the web); another site's page in their browser; a
program on their computer; someone who steals a token; someone on the
internet with no account.

**Trust boundaries.** The internet and the MCP endpoint; the tool and
Brando (the token); the browser and the consent screen (the session); one
site environment and another; a proposal and the content it changes (a
person's click in the admin).

What the endpoint does about each requirement in
[#2996](https://github.com/brandocms/brando/issues/2996):

1. **Off by default.** No route exists until the application calls
   `mcp_routes()`. Mounted, each site environment is off until turned on;
   while off, every MCP, OAuth and metadata path, and the consent screen
   before the admin pipeline touches the session, raises
   `Phoenix.Router.NoRouteError` before the token, the origin or the body is
   looked at. The application renders that exactly as it renders any path
   no route matches, with no cookie or header of the endpoint's own. One
   difference remains in applications whose router ends in `page_routes()`:
   there, an unknown `GET` path goes to the page catch-all, through the
   browser pipeline, while a disabled MCP `GET` path does not. Both answer
   404; their headers can differ. The endpoint's other paths are `POST`
   only, which the catch-all never matches.
2. **Only OAuth 2.1 with PKCE, through the normal login, with 2FA.** No API
   keys or static tokens: the only credential is an access token from the
   code flow. PKCE is required and S256 only (a missing or `plain` method is
   refused). The consent screen is behind the admin login with its second
   step, and refuses people without two-factor authentication.
3. **Per-user tokens with the user's own permissions.** A token belongs to
   one connection of one person. Every call loads the person again and runs
   the tools as them, so it never has more than they have in the admin;
   permission, two-factor authentication, account and switch are checked on
   every request. Access tokens last an hour; refresh tokens rotate, and a
   reused one revokes the connection; a connection lasts at most 90 days.
   Connected apps lists and revokes them, and a password change or "log out
   everywhere" revokes them all.
4. **Read and propose only.** A fixed list of the registry's tools, none of
   which approves, applies or deletes; `prepare_proposal` stores a proposal
   that only a person's click in the admin applies (the Assistant's version
   check and transaction). The exceptions are
   `brando_figma_import_images`, `brando_media_finish_upload` and
   `brando_media_import_url`, which add images to the media library before
   a proposal is applied, as an upload by the person would: only for
   someone who may create images, checked like an upload (type, contents,
   size, pixels), and never replacing or deleting an image.
   `cancel_proposal` changes only a proposal's status: it cancels the
   tool's own proposal while it is under review, and leaves content as it
   is. `preview_proposal` stores only a snapshot of a page, readable by
   anyone with its unguessable link for 15 minutes while the proposal is
   under review; it takes the permissions the admin's own review preview
   takes.
5. **Scoped per site and environment.** The endpoint URL names the site
   environment; it is the token's audience, and every token, code and
   connection records its site and environment. A token is looked up only
   with the resource of the endpoint it is presented at, and its site and
   environment must match, so a token for one site environment is unknown
   at another whatever ids are guessed. Tools run in its schema prefix and
   authorization scope. The consent screen names the site environment.
6. **Everything is logged.** Activity records every tool call (person, tool,
   result, token row id, the short summary its live page shows), connections,
   revocations and the switch; the
   person's security log records connecting and disconnecting. Proposals are
   marked with the tool's name.
7. **Rate limits.** Per connection and per person on the endpoint, per
   address on the token and revocation endpoints, per person on the consent
   screen. No tool calls a model, so there is no cost limit to keep.
8. **Transport hygiene.** HTTPS in production (the endpoint will not turn on
   without it). A browser `Origin` other than the site's own (or a configured
   one) gets 403. No CORS headers at all. A POST with a `Transfer-Encoding`
   gets 400, one without a `Content-Length` 411, and one over 512 KB 413, read from the header before the
   token is looked at (`Brando.MCP.BodyLimit` refuses it before the
   endpoint's parser too); results are bounded as in the Assistant. Tokens are read from the
   `Authorization` header only, never the query string. An upload URL is
   the one place a credential is in a URL (below).
9. **Security review.** This section, and the tests for the flow, token
   scope, revocation and cross-tenant access in `test/brando/mcp/`.

And the attacks the review asked about:

- **Stolen database.** Tokens and codes are SHA-256 hashes of 256-bit random
  values; a copy of the tables cannot be used to call the endpoint.
- **PKCE downgrade.** S256 is the only method, required on every request, and
  the verifier is checked (43–128 characters) with a constant-time compare.
- **Open redirect.** Brando sends a person back only to a redirect URI the
  client's own document lists: exactly, or for a loopback `http` address on
  any port. Only `https` and loopback `http` are accepted, without
  fragments. A client or redirect URI that does not check out gets an error
  page, never a redirect; so does any other mistake in the request, until the
  person clicks. The authorize step forwards only to Brando's own consent
  screen.
- **Consent CSRF and clickjacking.** The consent screen is a LiveView: its
  socket carries the session's CSRF token, and Allow is an event on it, not
  a link. The page sends `frame-ancestors 'none'` and `X-Frame-Options:
  DENY`. Allow asks for the password or a code when the session has not given
  one lately, and checks the whole request again before issuing a code.
- **Confused deputy and mix-up.** Each site environment is its own issuer
  and resource. A code is bound to its resource, client, redirect URI,
  challenge, user and site environment, and is only exchanged at that
  environment's token endpoint; `resource` must name that endpoint
  (`invalid_target` otherwise). The redirect carries `iss` (RFC 9207). Brando
  passes no token on to anything.
- **Client registration abuse.** There is no registration endpoint. Client
  documents are fetched only for a signed-in person who may connect, at most
  30 checks a minute, through the webhooks' address guard (public addresses,
  `https` on port 443, two seconds per DNS lookup, no redirects, five
  seconds, 5 KB) and are never stored. A `client_id` on the site's own host,
  its media or CDN host, or any site environment's domain is refused: a
  file uploaded there could pose as a client. A client's
  name is its own claim: the consent screen shows the host that published it
  and the redirect host, and warns about loopback addresses.
- **Tokens in logs, Activity and URLs.** Tokens never appear in a URL (codes
  only in the one redirect the client asked for), never in Activity (the
  token's row id), never in errors. Responses carry `Cache-Control:
  no-store`; the consent screen sends `Referrer-Policy: no-referrer`.
- **Timing.** Tokens and codes are found by their hash, and client ids,
  redirect URIs, resources and PKCE values are compared in constant time.
- **Refresh token reuse.** A refresh token works once. The exchange locks
  its row; a second use revokes the whole connection, except within ten
  seconds while the first answer's refresh token is unused, when the same
  answer is returned (a client refreshing twice at once). A reused code
  revokes the connection it made.
- **A leaked upload URL.** It carries a 256-bit random secret, of which
  only the SHA-256 is kept and which is compared in constant time; a wrong
  one answers as an unknown upload. It takes one PUT within 10 minutes, of
  at most the image config's size limit, of an image type the config
  takes, while its connection is good and its person may create images.
  Whoever holds it can at most put one image in place of the tool's: only
  the connection that prepared it can finish the upload, and the image is
  then in the library as any upload is, for a proposal a person reviews.
  The URL is never shown on the live page or in Activity, and Brando's own
  log has its secret filtered out; a proxy in front of the application logs
  what it is set to log.
- **Another connection.** An upload is found only for the connection that
  prepared it, at the site environment it was prepared for. Another
  connection's `brando_media_finish_upload` gets the answer for an upload
  that does not exist.
- **Oversized, unsized or slow bodies.** A declared length over the limit is
  refused before reading; the bytes are counted as they arrive and the PUT
  is cut off past the limit, when 64 KB take longer than 15 seconds to
  arrive, or 10 minutes after it started. JSON and form bodies are refused
  before the endpoint's parser reads them (with `Brando.MCP.BodyLimit`).
  What was written is removed, also when the client goes away mid-upload;
  when the request's process dies without a word (an HTTP/2 stream the
  peer closed, a node going down), the upload counts as failed once its
  10 minutes are up, and its bytes go with it when it is finished or swept.
- **Mislabelled files.** The type is read from the first bytes, whatever the
  name or `Content-Type` say, and the store checks it again with the
  config's types, the pixel limit and an SVG's contents.
- **Fetching an address (SSRF).** `brando_media_import_url` fetches only
  public `https` addresses through the webhooks' address guard, connects to
  the address it checked, follows no redirect and reads at most the size
  limit, so it cannot reach the server's own network or cloud metadata.
- **Revocation latency.** None: there is no token cache. Every request reads
  the token, the connection, the person, two-factor authentication, the
  permission and the switch from the database.
- **Two-factor authentication turned off after connecting.** Turning it off
  (or an administrator's reset, or losing the last passkey) revokes the
  person's connections; any other way it disappears, the next request is
  refused. A changed password and "log out everywhere" revoke them too.
- **Reading what the person cannot.** The tools that describe content types
  and modules answer only for content types the person may read (and
  modules only for someone who may edit a content type), for the Assistant
  and for connected tools alike. Entries they name are filtered the same
  way: `list_selection_options` lists only the entries the person may read,
  whatever the module's datasource returns, and `entry_outline` gives no
  title for an entry the outlined one chooses or links to that the person
  may not read, and leaves out such language versions.
- **Figma downloads (SSRF).** The Figma API is called at its fixed address.
  The image URLs it answers with are fetched through the webhooks' address
  guard (public `https` addresses only, the checked address connected to, no
  redirects), with a time limit and the image config's size limit (with
  `fit`, the import's own `fit_download_limit`), written to
  a temporary file and checked as an upload before anything is stored.
- **The Figma token and the Figma app.** A pasted token, the app's client ID
  and secret, and the connection's access and refresh tokens are encrypted at
  rest and bound to their site environment and column, so a copy of a
  column, or a ciphertext moved to another row, gives nothing. They reach
  only Figma's API, in a header (a pasted token in `X-Figma-Token`, an access
  token as `Authorization: Bearer`, the app's credentials as HTTP Basic
  authentication when the code is exchanged or the token renewed), and are
  never shown, logged or returned to a tool; `brando_figma_status` returns
  the handle of the account, not its email address. They give a tool what
  their account can open in Figma; a narrow account limits that.
- **Connecting Figma.** The `state` is random, kept only as a hash, used
  once, expires in ten minutes and belongs to the person, the session and the
  site environment that started; PKCE keeps an intercepted code from being
  exchanged elsewhere. The callback checks again that the person may manage
  the environment's settings, and saves nothing when the app or the
  connection changed meanwhile. Its route is not logged, so Figma's code
  stays out of the request log.
- **Prompt injection.** A tool following instructions from content can only
  read what the person can read and prepare proposals; a person reviews
  every change before it is applied.
