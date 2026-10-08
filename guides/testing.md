# Testing

`Brando.Test` is a toolkit for a Brando project's own tests. It renders
blocks and modules as the site does, builds valid entries for any blueprint,
drives an entry's admin form, logs in users with given rights, and replays
recorded AI calls so the content assistant and the AI helpers can be tested
without a model or a key.

The module ships with Brando and is compiled into every build. It does
nothing until a test calls it.

## Setting up

A Phoenix project has `test/support/data_case.ex` and
`test/support/conn_case.ex`. Add `use Brando.Test` to the `using` block of
both:

```elixir
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias MyApp.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MyApp.DataCase

      use Brando.Test
    end
  end

  # setup/1 and setup_sandbox/1 as Phoenix generated them
end
```

This imports the helpers below and `use_cassette/3`, and lets a test pick a
recorded AI cassette with `@tag cassette: "name"`.

In `config/test.exs`, keep tests away from live models:

```elixir
# A model call outside a cassette fails instead of reaching a provider.
config :brando, Brando.AI, client: Brando.AI.Cassette

# Where cassettes are read and written. This is the default.
config :brando, Brando.AI.Cassette, dir: "test/cassettes"
```

LiveView tests need `lazy_html` (a new Phoenix app has it):

```elixir
{:lazy_html, ">= 0.1.0", only: :test}
```

The test database needs Brando's migrations, as in development. Pages that
read the site's identity or SEO settings need them in the database:
create them in the test, or seed the test database once.

## Entries for any blueprint

You do not need a factory per schema. `insert_entry/3` creates a valid entry
through the blueprint's context (`create_project/2` and so on), with its
identifier, revision and rendered blocks, as the admin creates it:

```elixir
project = insert_entry(MyApp.Projects.Project, %{title: "Sommerro"})
```

Values come from, in order:

1. the attributes you pass;
2. the blueprint's own `factory %{...}` defaults;
3. defaults derived from the blueprint. Every required attribute gets a value
   of its type: a unique string or slug, the default language, a published
   status, today's date. Every required `belongs_to` relation gets an entry of
   its own, made the same way. A required image, file or video gets a record
   without a file on disk.

The `:creator` trait's creator is the `user:` you pass, or a new superuser.

```elixir
user = insert_user(role: :editor)
project = insert_entry(Project, %{status: :draft}, user: user)

# Params only, for your own create call
params = params_for(Project, title: "Sommerro")

# A valid struct that is not inserted (what it refers to is)
project = build_entry(Project)
```

An entry that does not validate raises with the changeset errors, so a
missing value is named.

Entries can start with blocks. Each item is a module, or a module with vars
and refs (see below):

```elixir
project =
  insert_entry(Project, %{title: "Sommerro"},
    blocks: [header_module, {quote_module, vars: %{"author" => "Ada"}}]
  )

project.rendered_blocks
```

`insert_block/3` adds a block to a saved entry and renders the entry again.

## Rendering blocks

`render_block/2` renders a block, or a module with its default content, to
HTML exactly as the site would: the configured parser, the Liquid pass,
footnotes, `$timestamp` and form delivery.

```elixir
test "the quote module credits its author" do
  html =
    render_block(quote_module,
      vars: %{"author" => "Ada"},
      refs: %{"text" => %{text: "<p>Hello</p>"}}
    )

  assert html =~ "<cite>Ada</cite>"
end
```

- `vars:` maps var keys to values. A boolean var takes a boolean; an image,
  file or video var takes the asset.
- `refs:` maps ref names to the ref block's data fields, a media struct for a
  media ref, or `false` to switch the ref off.
- `entry:` is the entry the template sees as `entry`.
- `conn:` is for templates that read `request`.

A var or ref the module does not have raises, listing the ones it has.

Modules are read from the database when rendering, so the module must be
saved. Create it with `Brando.Content.create_module/2`, or load the modules
your site defines.

## Admin forms

The form helpers drive an entry's form the way an editor does. Use them in a
`ConnCase` test that is not `async`, since the form's LiveView reads the
test's data through a shared sandbox:

```elixir
test "an editor changes a project's title", %{conn: conn} do
  project = insert_entry(Project, %{title: "Before"})
  {conn, _user} = log_in_as(conn, role: :editor)

  {view, _html} = open_form(conn, project)
  fill_form(view, Project, title: "After")
  add_block(view, Project, quote_module)

  assert {:ok, _path} = save_form(view, Project)
  assert Repo.get!(Project, project.id).title == "After"
end

test "a title is required", %{conn: conn} do
  {conn, _user} = log_in_as(conn)
  {view, _html} = open_form(conn, insert_entry(Project))

  assert {:error, %{title: [_]}} = save_form(view, Project, title: "")
end
```

- `open_form/3` mounts the update form for an entry, or the create form for
  a schema, and waits until it has rendered.
- `fill_form/4` fills fields by their blueprint names. A `belongs_to`
  relation takes the related id (`client: client.id`). A name the blueprint
  does not have raises.
- `add_block/4` adds a block from a module, as picking it in the block
  editor does, and returns the new block's uid.
- `save_form/4` saves as the browser does: the first submit collects the
  block fields, the second writes. It returns `{:ok, path}` or
  `{:error, errors}`, with the errors the form shows by field.
- `form_errors/2` reads the errors the form shows now.

A named form takes `form_id:` (and `path:` for its route).

## Users and rights

`insert_user/1` and `log_in_as/2` cover both authorization modes:

```elixir
# Legacy roles
{conn, user} = log_in_as(conn, role: :editor)

# Groups mode (config :brando, authorization_mode: :groups)
{conn, user} = log_in_as(conn, permissions: ["my_app.projects.read", "my_app.projects.update"])
```

With `permissions:`, the user joins a group of their own with exactly those
permissions. `log_in_as/2` adds `brando.admin.access`, which every admin user
needs. A key the permission catalogue does not have raises.
`log_in_user/2` logs in a user you already have.

## Recorded AI calls

The content assistant, alt text, translation and the other AI helpers call a
model through `Brando.AI`. In tests, a cassette answers those calls from a
JSON file under `test/cassettes/`:

```elixir
test "alt text is written for every language" do
  use_cassette "alt_text/harbour" do
    assert {:ok, %{values: values}} = Brando.Images.AltText.describe(image.id)
    assert values["no"] =~ "ferje"
  end
end

@tag cassette: "assistant/add_quote"
test "the assistant adds a quote", %{conn: conn} do
  # …the LiveView, its tasks and the assistant's run all use the cassette
end
```

The cassette is scoped to the test process and every process it starts —
LiveViews, their `start_async` tasks, task supervisors and inline jobs — so
tests that use one can run `async`.

### Recording

The first time, record the cassette against the real model. This needs the
model and its key configured in the test environment, from the environment
and never in the code:

```
ANTHROPIC_API_KEY=… BRANDO_CASSETTE_MODE=record mix test test/my_app/alt_text_test.exs
```

After that, the test replays the file without a key. When the model is
configured but no key is set, Brando uses a placeholder while a cassette
replays. Commit the cassettes.

The mode is one of:

- `replay`, the default: answer from the file. A request that matches no
  recording fails the test, naming the cassette and where the request
  differs from the closest recording.
- `record`: call the model and write the file at the end of the test.
- `auto`: replay when the file exists, otherwise record.

Set it with `BRANDO_CASSETTE_MODE`, the `mode:` option or
`config :brando, Brando.AI.Cassette, mode: …`, in that order of precedence.

### What a cassette holds

Each interaction is a request and a reply. The request is normalised: the
model, the system prompt, the messages, the tools (as names and a digest of
their definitions) and the model parameters. Ids, uids, UUIDs and
timestamps in tool results are blanked out, and images become a digest, so a
recording matches a later run against a different database. The reply keeps
its text, tool calls, usage and finish reason. Streams are recorded and
replayed chunk by chunk.

API keys and credentials are never written: the request carries no key or
HTTP options, values under credential keys are replaced, and every known
key is scrubbed from the text before the file is written.

Cassettes are plain JSON, so a small change can be made by hand, and a
failing test shows what to change.

### Ids that differ between runs

A recorded tool call names entries by id, and those ids differ from run to
run. Bind them by name: on recording they are written as `"{{name}}"`, and on
replay filled in from the test's own data.

```elixir
use_cassette "assistant/add_quote", bindings: %{page: page.id, module: "local:#{module.id}"} do
  …
end

# With a tag, bind once the data exists
Brando.AI.Cassette.bind(page: page.id)
```

### Matching

By default the model, system prompt, messages, tools and parameters must all
match. `match_on:` narrows it, for a test about the conversation rather than
the prompt wording:

```elixir
use_cassette "assistant/add_quote", match_on: [:model, :messages, :tool_names] do
```

`match_on:` also takes functions of the recorded and the new request.
`ignore_keys:` blanks out other values that change between runs, such as a
list of suggested ids. `allow_unused: false` fails the test when recorded
interactions were not played.

### Replies that depend on the prompt

For a reply that depends on what was asked, use a stub instead of a file:

```elixir
Brando.AI.Cassette.stub(fn request ->
  if Enum.any?(request["messages"], &(&1["content"] =~ "Norwegian")), do: "Hei", else: "Hello"
end)
```

## Tips

- Prefer `insert_entry/3` over inserting structs. It goes through the same
  changeset, identifier and rendering as the admin, so a test sees what an
  editor would.
- Test a module's template with `render_block/2`, and a page's whole output
  with a request to the page.
- Form tests are slower than `render_block/2` and context tests. Keep them
  for what only the form does.
- Keep cassettes small: one flow per cassette, named after what it tests.
- Record with the model the site uses, so a cassette shows what that model
  does with the prompt.
