# Content assistant

**System → Assistant** lets an editor describe content changes in a
conversation: which entries to change, which media to use and where it goes.
A model prepares the changes as a proposal. The editor reviews it entry by
entry and applies it with one explicit click. Nothing is saved before that.

Screenshots: [empty workspace](../docs/admin-ui/assistant-empty-desktop.png),
[review](../docs/admin-ui/assistant-review-desktop.png),
[needs changes](../docs/admin-ui/assistant-needs-changes-desktop.png),
[media library](../docs/admin-ui/assistant-library-desktop.png),
[page preview](../docs/admin-ui/assistant-preview-desktop.png),
[applied](../docs/admin-ui/assistant-applied-desktop.png) and
[mobile](../docs/admin-ui/assistant-applied-mobile.png).

<!-- usage-rules:start topic="assistant-mcp" -->

## Configure a model

The assistant uses `Brando.AI`'s providers and keys:

```elixir
config :brando, Brando.AI,
  providers: [anthropic: [api_key: System.get_env("ANTHROPIC_API_KEY")]]

config :brando, Brando.AI.Agent,
  model: "anthropic:claude-opus-5-5",
  max_steps: 12,                    # model calls per message
  max_tokens: 4096,                 # output tokens per model call
  run_token_budget: 300_000,        # input + output tokens per message
  monthly_token_budget: 5_000_000,  # per site/environment; nil for none
  guidance: MyApp.AssistantGuidance, # see "Site guidance" below
  prices: [input: 5.0, output: 25.0]
```

`prices` are in USD per million tokens and only estimate cost for display and
records. The budgets are what stop spending: before every model call, a run
reserves an estimate against its own budget and the site/environment's monthly
budget, and stops when either would be exceeded. After the call, the
provider's reported usage replaces the estimate.

Without a configured model and key, the menu item is hidden and the screen
explains what is missing.

**Providers.** The model is a ReqLLM `"provider:model"` spec, with its key
under `providers` (or `api_key` in the agent's own configuration). Anthropic
is the supported provider: the assistant was run against a real
`anthropic:claude-opus-5-5` on 9 October 2026, and its prompt caching is
turned on for Anthropic only. Other providers that ReqLLM supports with tool
calling may work, but have not been checked with the assistant.

<!-- usage-rules:end -->

## Permissions

With groups authorization, the assistant needs **Content assistant → use**
(`brando.assistant.use`). New capabilities are never added to existing groups
automatically, so grant it to the groups that should have it. Editing the
site guidance needs **Content assistant → configure**
(`brando.assistant.configure`), which only superusers have until a group is
granted it; without groups authorization, only superusers. Everything the
assistant reads or proposes is also checked against the editor's own
permissions. It cannot see entries the editor cannot edit, create content
types the editor cannot create, or change a published page unless the editor
may publish.

## How it works

- **The model runs in the Brando backend.** It reaches Brando only through the
  tools in `Brando.Content.Proposals.Tools`, called in-process as the editor.
  The Assistant uses no MCP endpoint, route or port: a production release
  needs no MCP URL, no `mcp_routes()` and no listener for it, and works the
  same with the [remote endpoint](mcp.md) off. The only connection it makes is
  the outgoing call to the model provider. The model can search and read
  entries, modules and media, and prepare a proposal. It cannot approve or
  apply anything.
- **Proposals are stored and versioned.** Each proposal records its
  operations, the fingerprints of the entries it read and the versions of the
  modules it builds blocks from. Asking for an adjustment creates a new
  version, and the previous one can no longer be applied.
- **Applying is atomic.** The Apply button approves exactly the version on
  screen and applies it in one transaction. If an entry or module changed
  after the proposal was prepared, nothing is written; ask the assistant to
  prepare it again. New entries are created as drafts. Changes to a published
  entry go live, and the review says so before you apply.
- **Attachments keep their names.** Media uploaded or picked in the
  conversation is named `image1`, `image2`, `video1` … in the order it was
  chosen, not the order uploads finish. Refer to these names in messages.
  Attaching the same image again keeps its name.
- **Content is data.** Titles, texts and file names the assistant reads never
  change its instructions.
- **It speaks the editor's language.** Progress such as "Thinking" and the
  assistant's notices use the editor's admin language; the model is told to
  answer in the editor's language. New entries get the conversation's content
  language unless the editor names another.

<!-- usage-rules:start topic="assistant-mcp" -->

## Proposals from connected tools

Tools connected over MCP can prepare proposals too: Claude, ChatGPT or Claude
Code through the remote endpoint, once an administrator turns it on and the
person connects them ([Connected AI tools](mcp.md)), and a coding agent in
development through BrandoMCP's stdio server (`mix brando.mcp`, as a named
Brando user; see the BrandoMCP README). The tools read content and prepare
proposals; a person reviews and applies them in the Assistant.

<!-- usage-rules:end -->

Their proposals belong to that user but to no conversation, so the Assistant
lists them apart:

- **From connected tools** sits beside the conversation's title, with the
  number of proposals waiting for review. It opens a list of them in place of
  the conversation, newest first, each with its summary, where it came from
  ("From Claude Code via MCP") and its state: waiting for review, applied,
  undone or expired. Discarded and superseded versions are left out.
- **The review is the Assistant's own.** Choose a proposal to review it entry
  by entry, preview its pages, leave changes out, share it, apply it with the
  usual version check, or discard it to reject it. It is marked with its
  origin in the AI suggestion look. There is no Adjust: to change it, ask the
  tool again, and its next proposal replaces this one as a new version.
- **The tool is told where to look.** `prepare_proposal`'s result gives the
  address of the proposal under "From connected tools".
- **Who sees them.** Only the user the tool ran as, in the site and
  environment it was prepared in, and only with **Content assistant → use**,
  like the Assistant itself. Without a configured model the Assistant has no
  conversation, but its menu item still appears while proposals wait.
- **Activity** records an applied proposal from MCP with the tool as its
  source, "Claude Code" with an MCP badge, the proposal, and the person who
  approved it underneath, who can open the proposal from there.

Each proposal records its origin: `"assistant"`, or `"mcp"` with the tool's
name: over stdio the MCP client's `clientInfo` name, through the remote
endpoint the name in the client's metadata document. A tool call that
reaches `Proposals.Tools` without a conversation is recorded as MCP unless
the caller names its origin in the `Context`:

```elixir
context = %Brando.Content.Proposals.Tools.Context{actor: user, origin: :mcp, client: "Claude Code"}
Brando.Content.Proposals.Tools.call("prepare_proposal", args, context)
```

`Proposals.list_external/2` and `Proposals.count_external/1` list and count
these proposals for a user.

## Language versions

An entry's outline and its review card list its other language versions
(alternates and members of its [synchronized translation
group](i18n.md#synchronized-translations)). The review card says for each
whether the proposal changes it, it follows the source, or it stays unchanged.

When a change touches an entry with language versions, the assistant asks
whether it should apply to them too, unless you have already said. Versions
that are not synchronized change only when the proposal changes them, so the
assistant writes the matching change into the same proposal, in their
language. When the changed entry is a synchronized source, its synchronized
translations need no matching change: applying runs the same after-save work
as an editor's save, so they get pending versions with the source's structure,
media and new text to translate.

## Build with AI from the block editor

A block field shows **Build with AI** next to its label when the assistant
has a model and the editor may use it. It opens the assistant in a new tab,
with that entry and block field selected. The conversation panel shows the
entry, its content type, the block field and the language. Unless you name
other entries, the assistant proposes its changes there.

- **The assistant reads the saved entry.** Edits you have not saved stay in
  the editor's tab and are not included. The block field says so while it has
  unsaved block changes. Save first if the assistant should build on them.
- **A new entry has to be saved first.** Until then the button is disabled
  and says why.
- **Opening the assistant changes nothing.** The conversation starts with your
  first message. The proposal is reviewed and applied in the assistant as
  usual, and applying fails if the entry was saved again after the proposal
  was prepared.

The entry is checked like any other target: the editor needs permission to
change it. Direct insertion into an open, unsaved editor is not supported.

## Site guidance and instructions

Sites usually have conventions for building content from their modules.
There are two places for them, and the assistant reads both.

### In the admin

**Configuration → Assistant guidance** holds the guidance of the current
site and environment. Staging and production each have their own.

- **Every save is a version.** The history shows who saved what and when.
  **Load into editor** brings back an earlier version; save it to use it
  again.
- **Copy from another site or environment** loads that guidance into the
  editor. It lists the sites and environments where you may also edit
  guidance. Nothing changes until you save, and the version records where it
  was copied from.
- **Editors can read it.** The assistant shows the guidance in use under
  **Site guidance in use**, so nobody has to guess what steers it.
- Only users who may configure the assistant see the screen: superusers by
  default (see [Permissions](#permissions)). Guidance is trusted as
  instructions for everyone's assistant, so grant this sparingly.

<!-- usage-rules:start topic="assistant-mcp" -->

### In the code

Developers can ship a baseline in `guidance`, as a string or as a module
implementing `Brando.AI.Agent.Guidance`. The admin screen shows it
read-only. Where the two conflict, the admin guidance applies: it is the one
kept up to date as modules change.

```elixir
defmodule MyApp.AssistantGuidance do
  @behaviour Brando.AI.Agent.Guidance

  @impl true
  def guidance(%{content_type: MyApp.Articles.Article}) do
    """
    - Start an article with the "Article lede" module for its introduction.
    - A long introduction goes partly in "Article lede" and continues in
      "Article text".
    - Portrait image pairs use "Two images" with the narrow setting on.
    """
  end

  def guidance(_scope), do: nil
end
```

The module is called for every model call, with the site and environment keys
(`nil` without tenancy) and the content type of the selected entry, if the
conversation has one. One application can give each site its own guidance.
Guidance is limited to 12,000 characters. A guidance module that fails is
logged and left out.

<!-- usage-rules:end -->

Name modules, slots and settings the way editors see them. The assistant
matches the names against the modules the block field allows. If a name
matches nothing, matches several modules, or needs a setting the module does
not have, the assistant says so and asks. It does not invent module ids, and
every proposal is still checked and reviewed.

**Instructions for one entry or request** are written in the conversation:
"Put image3 and image4 after the lede", "Use the quote module for the last
paragraph". Open the conversation from the entry's block editor so the
assistant knows which entry you mean.

When instructions conflict, this order applies, highest first:

1. Permissions, the proposal checks and your approval. Nothing overrides them.
2. Your messages. A later message replaces an earlier one where they conflict.
3. The selected entry.
4. The site guidance: the admin guidance, then the guidance in the code.

Guidance is written by the site's developers and administrators and is
trusted as instructions.
Entry text, file names, captions and other content the assistant reads are
data: instructions in them are ignored.

## Media from a folder

Ask for "all the images in the a_form folder" and the assistant attaches the
folder's media to the conversation:

- **The folder is looked up by name** in the media library of the current
  site/environment, the same folders the image and video pickers show. A path
  such as `projects/a_form` narrows it down. When several folders match, the
  assistant asks which one you mean. An empty folder is reported as empty.
- **All means all.** The assistant attaches up to 100 items at a time and
  continues until the folder is done, then says how many it attached.
- **Subfolders are only included when you ask for them.**
- **The order is fixed:** images by file name, videos in upload order. The
  media gets the next free names (`image1`, `image2` …); media that was
  already attached keeps its name, so asking again changes nothing.
- **Only media you may see is attached.** Deleted items are left out, and
  anything that cannot be attached is reported.

The attached media appears under the conversation, and the proposal shows
which of it is used. Nothing is placed until you apply the proposal.

## Page previews

**Preview page** on an entry card renders the entry as proposed, through the
site's own [live preview](live_preview.md) targets and templates. Nothing is
saved to do this.

- **Entry tabs** switch between the entries in the proposal. The apply bar
  keeps describing the whole batch.
- **Before / Proposed** compare the saved version with the proposal. Before is
  the version the proposal was prepared from; if the entry has changed since,
  the preview says so and the proposal must be prepared again. A new entry has
  no Before.
- **Views** appear when a content type has more than one preview target, for
  example the page and its listing.
- **Desktop / Mobile** set the frame width. **Show changes** outlines the
  inserted and changed blocks. The outline is drawn over the page, not into
  it, so it does not change the layout.

Content types without a preview target show their changes in the card only.
A template that fails to render shows the error and a retry, never a
substitute image. Previews are private to the editor who prepared the
proposal, and are removed when another preview replaces them or the proposal
is applied.

## What a proposal can do

- Create entries, as drafts.
- Change fields of existing entries, including their status where the editor
  may set it. Publication times and block fields are not set this way.
- Insert blocks from the modules a block field allows: as a root block, or
  into a multi module, a container or a slot; at the end, or before or after
  another block.
- Move, copy and delete blocks, children included, and turn a block or one of
  its slots on or off.
- On new and existing blocks, at any depth:
  - set text in text, header, markdown, html, svg and map slots;
  - put images, videos and files in media slots, and set a gallery's whole,
    ordered content;
  - set variables: text, boolean, select, colour, date, image, video, and
    links to a URL or an entry;
  - change a slot's settings: a heading's level, a picture's alt text, title,
    credits or link, a video's autoplay or loop, a gallery's display;
  - replace a table's rows, and choose the entries a selection datasource
    shows;
  - set a block's anchor and its description.

It does not delete entries. A link to an entry created in the same proposal is
reported as a problem, because the new entry is a draft.

## Limits

These are the defaults, and what the tests check:

- **A message** gets at most 12 model calls (`max_steps`), 4,096 output
  tokens per call (`max_tokens`) and 300,000 tokens in all
  (`run_token_budget`). The step limit ends the run with "I stopped after 12
  steps", and the editor can tell it to continue.
- **A month** has no token limit until `monthly_token_budget` is set. It
  counts every run in the site and environment, including the tokens
  reserved for calls in flight.
- **A tool result** is at most 24 KB. A larger one is replaced by a request to
  narrow it. Searches return at most 20 results, an entry's outline shrinks
  to about 20 KB, and a folder is attached 100 items at a time.
- **A proposal** can be applied for 24 hours, and its review links last as
  long. After that it must be prepared again.
- **A model call** waits at most two minutes for the provider
  (`receive_timeout`) and is tried again once (`max_retries`) when it timed
  out, lost its connection or found the provider overloaded. An overloaded
  provider can ask for a wait before that retry. Then the run fails.
- **One run at a time** per conversation, in every tab and on every server.
  A running run shows it is alive every 15 seconds (`heartbeat`); one that
  has not for a minute died with its server and is marked interrupted.

## Operating the assistant

Nothing the assistant does is saved before an editor applies a proposal, so
a run that fails leaves the content as it was. Each run is stored in
`ai_runs` with its status, token counts, estimated cost and error. The log has
the details of a run that failed ("Content agent run … failed").

- **A run fails or the provider is down.** The conversation says "Something
  went wrong" with the provider's error. Send the message again once the
  provider answers. The conversation, its attachments and the proposal under
  review are kept. To turn the assistant off meanwhile, remove its model or
  key, or set `monthly_token_budget` to `0`.
- **The budget runs out.** The run stops before its next model call and says
  the token budget is used up; the steps it took are kept. For one message,
  ask for less at a time, or raise `run_token_budget`. For the month, wait
  for the next one or raise `monthly_token_budget`. Set to `0`, it stops
  every run before its next model call.
- **A run seems stuck.** After a reconnect, the conversation shows the run
  that is still working, with **Stop**. A stopped run shows "Stopping…"
  until its model call returns (at most about four minutes, see
  [Limits](#limits)), since it may still add to the conversation; until then
  no new message can be sent, in any tab. A run left behind by a
  restart or a deploy lets the conversation go a minute after its server
  stopped, and the page notices without a reload.
- **Apply is refused because something changed.** An entry or module was
  saved after the proposal was prepared, or the proposal expired. Nothing was
  written. Ask the assistant to prepare it again.
- **Apply fails partway.** Applying is one transaction, so nothing was
  written. The error names the cause, such as an address another page took in
  the meantime. Fix it and click **Apply** again. A second click, or one in
  another tab, after the proposal was applied writes nothing more.
- **Applied changes were wrong.** **Undo** on the applied proposal puts every
  entry back and deletes the entries it created, unless an entry was changed
  again after it was applied.
- **Someone loses access.** Taking away **Content assistant → use**, or an
  editor's permission for a content type, applies to the next tool call and
  stops the run before its next model call. Their proposals can no longer be
  applied by them.

<!-- usage-rules:start topic="assistant-mcp" -->

## For developers

`Brando.Content.Proposals` can be used without the assistant:

```elixir
alias Brando.Content.Proposals

{:ok, proposal} = Proposals.propose(operations, user, summary: "…")
{:ok, _} = Proposals.approve(proposal.id, proposal.version, user)
{:ok, receipt} = Proposals.apply(proposal.id, proposal.version, user)
```

`Brando.Content.Proposals.Preview` renders a proposed or saved entry through
the site's live-preview targets without saving it. BrandoMCP exposes the same
tools in-process, for an actor the host provides, and over stdio to local
coding agents in development; their proposals are reviewed under
[From connected tools](#proposals-from-connected-tools).

<!-- usage-rules:end -->
