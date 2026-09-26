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
  There is no MCP endpoint, route or port. The model can search and read
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
- Change fields of existing entries, except status, publication times and
  block fields.
- Insert blocks from the modules a block field allows: at the end, or before
  or after another block.
- Set text in text and header slots, images and videos in media slots, and
  string, text, boolean and select variables. This works on new blocks and on
  existing top-level blocks.

It does not delete entries or blocks, reorder blocks, edit nested blocks or
galleries, or insert multi modules. Links from blocks to entries created in the
same proposal are reported as problems, because the new entry is a draft.

## For developers

`Brando.Content.Proposals` can be used without the assistant:

```elixir
{:ok, proposal} = Proposals.propose(operations, user, summary: "…")
{:ok, _} = Proposals.approve(proposal.id, proposal.version, user)
{:ok, receipt} = Proposals.apply(proposal.id, proposal.version, user)
```

`Brando.Content.Proposals.Preview` renders a proposed or saved entry through
the site's live-preview targets without saving it. BrandoMCP exposes the same
tools to developer clients in-process, for an actor the host provides.
