defmodule Brando.Repo.Migrations.Brando198FixLegacyBlockSources do
  use Ecto.Migration

  @moduledoc """
  A block's `source` names the join schema that ties it to its entry, as a
  module — `"Elixir.Brando.Pages.Page.Blocks"` — which is what Brando writes
  for every block it creates and what it reads back to find a block's owner.

  Migration 108 wrote the join *table* there instead (`"pages_blocks"`,
  `"projects_description"`), so every block it converted from the legacy
  Villain format named a module that does not exist. Those blocks still
  render, but nothing can work out which entry holds them:

  - frontend edit opens them as "This block could not be found";
  - `Brando.Content.Blocks.list_orphaned_blocks/0` reports them all orphaned;
  - a change to an identifier, fragment or global they reference does not
    queue their entries for rendering again.

  This rewrites each table name to its join schema, found through the
  application's blueprints (and Brando's own Page and Fragment), in every
  site environment. Sources that already name a module, or name a table no
  blueprint joins through, are left alone.
  """

  def up do
    for prefix <- prefixes(), {table, module} <- sources() do
      set_source(prefix, table, module)
    end
  end

  def down do
    for prefix <- prefixes(), {table, module} <- sources() do
      set_source(prefix, module, table)
    end
  end

  defp set_source(prefix, from, to) do
    repo().query!(
      ~s(UPDATE "#{prefix}".content_blocks SET source = $1 WHERE source = $2),
      [to, from]
    )
  end

  # `{join table, join schema}` for every blocks field of every blueprint.
  defp sources do
    for schema <- Brando.Blueprint.list_blueprints(:include_brando),
        Code.ensure_loaded?(schema),
        function_exported?(schema, :__blocks_fields__, 0),
        %{name: field} <- schema.__blocks_fields__(),
        join = Module.concat([schema, field |> to_string() |> Macro.camelize()]),
        Code.ensure_loaded?(join),
        function_exported?(join, :__schema__, 1),
        uniq: true do
      {join.__schema__(:source), to_string(join)}
    end
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
