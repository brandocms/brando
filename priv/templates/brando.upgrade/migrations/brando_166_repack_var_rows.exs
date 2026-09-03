defmodule Brando.Repo.Migrations.Brando166RepackVarRows do
  use Ecto.Migration

  @moduledoc """
  Repairs the `new_row` backfill that brando_156 got backwards.

  That migration set `new_row = TRUE` on every var, which puts each one on a
  line of its own. Nothing carried an authored row break before it ran, and
  `Brando.Content.Var.Layout.pack/1` derives rows by packing left to right —
  breaking whenever the next var would overflow 12 units or 4 slots. So a false
  `new_row` everywhere is what reproduces the dense grid the vars had before.

  brando_156 is fixed too, so a site upgrading from further back never sees the
  broken state and this migration finds nothing to do.

  Only groups where *every* var is still `new_row = TRUE` are touched. Once an
  author has laid out a module by hand, at least one var in it is false, and
  that group is left exactly as they left it.
  """

  # A var hangs off exactly one owner. Two vars are laid out together when every
  # owner column matches — `IS NOT DISTINCT FROM` so the NULLs compare equal.
  @owner_columns ~w(
    page_id block_id module_id global_set_id palette_id
    table_template_id table_row_id menu_item_id
  )

  def up do
    execute(repack_sql())
  end

  # Restoring the broken state would be the only faithful inverse, and it would
  # overwrite any layout authored since. Rolling back leaves the repair in place.
  def down, do: :ok

  defp repack_sql do
    owner_match =
      Enum.map_join(@owner_columns, "\n        AND ", fn col ->
        "o.#{col} IS NOT DISTINCT FROM v.#{col}"
      end)

    """
    DO $$
    DECLARE target_schema text;
    BEGIN
      FOR target_schema IN
        SELECT 'public'
        UNION ALL
        SELECT nspname FROM pg_namespace
        WHERE nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        IF to_regclass(format('%I.content_vars', target_schema)) IS NOT NULL THEN
          EXECUTE format('
            UPDATE %I.content_vars v
               SET new_row = FALSE
             WHERE v.new_row IS TRUE
               AND NOT EXISTS (
                 SELECT 1 FROM %I.content_vars o
                  WHERE o.new_row IS NOT TRUE
                    AND #{owner_match}
               )', target_schema, target_schema);
        END IF;
      END LOOP;
    END $$;
    """
  end
end
