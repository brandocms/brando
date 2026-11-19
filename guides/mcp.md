# Connected AI tools (remote MCP)

Brando can let people connect Claude, ChatGPT, Claude Code, VS Code and other
[MCP](https://modelcontextprotocol.io) clients to a site. A connected tool
reads content and prepares proposals, as the person who connected it; the
person reviews and applies the proposals in the Assistant, under **From
connected tools**. Nothing a tool does saves, publishes or deletes content.
With a Figma token, a tool can also read a Figma frame and import its images
into the media library, to build an entry from a design (see
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
`describe_content_type`, `search_entries`, `entry_outline`, `list_modules`,
`describe_module`, `list_entry_media`, `list_selection_options`,
`search_assets`, `find_media_folders` and `prepare_proposal`. The tools that
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
result. Proposals
are marked with the tool's name, "From Claude via MCP", and wait under
**Assistant → From connected tools**. `prepare_proposal` answers with
`review_url`, the proposal's review there, and, when an entry the proposal
creates or changes has a page preview, `preview_url`: the review opened on
the first such entry's page (`?preview=<entry key>`), which is the link to
give the person.

With a Figma token (below), two more: `brando_figma_read_frame` and
`brando_figma_import_images`.

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
token). People who manage connected tools see these under **Configuration →
Activity**.

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
  `Figma/<frame name>` under the default image config's upload path, and
  answers with each image's asset for the proposal and the layers that show
  it. An image the library
  already has (the same file, for the same config) is reused, so importing a
  frame twice adds nothing. It imports at most eight images per call; the
  tool calls again for the rest. The images are added when the tool imports
  them, before anyone applies the proposal, and stay in the library if the
  proposal is discarded. Importing needs permission to upload images.
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
Figma**, below the token. Every save is a version, as with the Assistant's
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

### Add the token

The tools call Figma with one access token per site environment, under
**Configuration → Integrations → Connected AI tools → Figma**, which takes
the same **Connected AI tools → Manage** permission as the switch. Create it
in Figma under **Settings → Security → Personal access tokens**, with read
access to file content (`file_content:read`), on the account of someone who
can open the files to import. Figma limits how often its API answers by the
owner's seat and plan: use the account of someone with a Full or Dev seat,
since other seats get far fewer calls.

The token is stored encrypted with `Brando.Crypto`, bound to its site
environment, and never shown again: the screen shows its last four
characters, when it was added and by whom. Adding, replacing and removing it
asks for the password or a code when the session has not given one lately,
and is recorded in Activity (without the token). Without a token, the Figma
tools answer that an administrator adds one. Removing it keeps the images
already imported.

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
  allowed_origins: []             # browser origins allowed besides the site's own
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
   check and transaction). The one exception is
   `brando_figma_import_images`, which adds images to the media library
   before a proposal is applied, as an upload by the person would: only for
   someone who may upload images, into the frame's own folder, checked like
   an upload (type, contents, size, pixels), at most eight a call, and never
   replacing or deleting an image.
5. **Scoped per site and environment.** The endpoint URL names the site
   environment; it is the token's audience, and every token, code and
   connection records its site and environment. A token is looked up only
   with the resource of the endpoint it is presented at, and its site and
   environment must match, so a token for one site environment is unknown
   at another whatever ids are guessed. Tools run in its schema prefix and
   authorization scope. The consent screen names the site environment.
6. **Everything is logged.** Activity records every tool call (person, tool,
   result, token row id), connections, revocations and the switch; the
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
   `Authorization` header only, never the query string.
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
  redirects), with a time limit and the image config's size limit, written to
  a temporary file and checked as an upload before anything is stored.
- **The Figma token.** Encrypted at rest and bound to its site environment, so
  a copy of the column, or a ciphertext moved to another row, does not give
  the token. It reaches only Figma's API, in a header, and is never shown,
  logged or returned to a tool. It gives a tool what its owner can open in
  Figma; a token for a narrow account limits that.
- **Prompt injection.** A tool following instructions from content can only
  read what the person can read and prepare proposals; a person reviews
  every change before it is applied.
