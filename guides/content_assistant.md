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
automatically, so grant it to the groups that should have it. Everything the
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
- **Content is data.** Titles, texts and file names the assistant reads never
  change its instructions.

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
