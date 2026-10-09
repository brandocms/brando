defmodule Brando.Test do
  @moduledoc """
  Test helpers for Brando projects: render blocks, build entries for any
  blueprint, drive admin forms, log in with given rights, and replay
  recorded AI calls.

  Add `use Brando.Test` to the `using` block of your `DataCase` and
  `ConnCase`:

      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate

        using do
          quote do
            use Brando.Test
            # …
          end
        end
      end

  It imports the functions below and `Brando.AI.Cassette.use_cassette/3`,
  and lets a test pick a cassette with `@tag cassette: "name"`. The module
  is compiled into every build but does nothing until a test calls it.

  | Helper | Does |
  |---|---|
  | `render_block/2` | renders a block or module to HTML as the site does |
  | `build_block/2`, `insert_block/3` | a block from a module, unsaved or added to an entry |
  | `params_for/3`, `build_entry/3`, `insert_entry/3` | valid entries for any blueprint |
  | `insert_user/1`, `grant_permissions/2` | users with a legacy role or group permissions |
  | `log_in_user/2`, `log_in_as/2` | a conn logged in to the admin |
  | `open_form/3`, `fill_form/4`, `add_block/4`, `save_form/4`, `form_errors/2` | an entry's admin form |
  | `use_cassette/3` | recorded AI calls, see `Brando.AI.Cassette` |

  See the testing guide for setting up a project.
  """

  alias Brando.Test.{Blocks, Factory, Forms, Users}

  defmacro __using__(_opts) do
    quote do
      import Brando.Test
      import Brando.AI.Cassette, only: [use_cassette: 2, use_cassette: 3]

      setup {Brando.AI.Cassette, :setup_tags}
    end
  end

  # Blocks
  defdelegate render_block(block_or_module, opts \\ []), to: Blocks
  defdelegate build_block(module, opts \\ []), to: Blocks
  defdelegate insert_block(entry, module, opts \\ []), to: Blocks

  # Entries
  defdelegate params_for(schema, attrs \\ %{}, opts \\ []), to: Factory
  defdelegate build_entry(schema, attrs \\ %{}, opts \\ []), to: Factory
  defdelegate insert_entry(schema, attrs \\ %{}, opts \\ []), to: Factory

  # Users
  defdelegate insert_user(attrs \\ []), to: Users
  defdelegate grant_permissions(user, permissions), to: Users
  defdelegate log_in_user(conn, user), to: Users
  defdelegate log_in_as(conn, attrs \\ []), to: Users

  # Admin forms
  defdelegate fill_form(view, schema, attrs, opts \\ []), to: Forms
  defdelegate add_block(view, schema, module, opts \\ []), to: Forms
  defdelegate save_form(view, schema, attrs \\ %{}, opts \\ []), to: Forms
  defdelegate form_errors(view_or_html, schema), to: Forms
  defdelegate await_selector(view, selector, timeout \\ 2_000), to: Forms

  @doc """
  Mount the admin form for an entry (its update form) or a schema (its
  create form), wait until it has rendered, and return `{view, html}`.

  An entry with many blocks arrives in steps — its fields first, then its
  blocks, loaded asynchronously — so a bare `live/2` can return the form
  with its blocks still loading.

  Options: `path:` and `form_id:` for a named form. A macro, as
  `Phoenix.LiveViewTest.live/2` is: like `live/2`, it needs the test's
  `@endpoint` and `Phoenix.ConnTest` imported, as a `ConnCase` has them.
  """
  defmacro open_form(conn, schema_or_entry, opts \\ []) do
    quote do
      require Phoenix.LiveViewTest

      {path, form_id} = Brando.Test.Forms.form_target(unquote(schema_or_entry), unquote(opts))
      {:ok, view, _html} = Phoenix.LiveViewTest.live(unquote(conn), path)
      Phoenix.LiveViewTest.render_async(view, 5_000)
      {view, Brando.Test.Forms.await_selector(view, "##{form_id}_form input")}
    end
  end
end
