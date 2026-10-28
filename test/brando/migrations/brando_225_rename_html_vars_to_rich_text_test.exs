defmodule Brando.Migrations.RenameHtmlVarsToRichTextTest do
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @migration Application.app_dir(
               :brando,
               "priv/templates/brando.upgrade/migrations/brando_225_rename_html_vars_to_rich_text.exs"
             )

  setup_all do
    [{module, _bytecode}] = Code.compile_file(@migration)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    %{migration: module}
  end

  defp insert(type, value) do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO content_vars (type, key, label, value, inserted_at, updated_at) " <>
          "VALUES ($1, 'k', '{}', $2, now(), now()) RETURNING id",
        [type, value]
      )

    id
  end

  defp stored(id), do: Repo.query!("SELECT type, value FROM content_vars WHERE id = $1", [id]).rows

  test "renames html vars to rich_text and leaves their values and other vars", %{migration: migration} do
    html = insert("html", "<p>Body</p>")
    text = insert("text", "Text")

    version = System.unique_integer([:positive])
    Ecto.Migrator.up(Repo, version, migration, log: false, migration_lock: false)

    assert stored(html) == [["rich_text", "<p>Body</p>"]]
    assert stored(text) == [["text", "Text"]]

    Ecto.Migrator.down(Repo, version, migration, log: false, migration_lock: false)
    assert stored(html) == [["html", "<p>Body</p>"]]
  end
end
