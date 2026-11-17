defmodule Brando.Migrations.FixLegacyContentDataTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @migration Application.app_dir(
               :brando,
               "priv/templates/brando.upgrade/migrations/brando_147_fix_legacy_content_data.exs"
             )

  @extensions ["p", "h4", "list", "link", "bold", "italic"]

  setup_all do
    [{module, _bytecode}] = Code.compile_file(@migration)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    %{migration: module}
  end

  defp rows(sql, params \\ []), do: Repo.query!(sql, params).rows

  # The Legacy Content Wrapper as brando_108 made it, after brando_125
  defp wrapper! do
    [[id]] =
      rows("""
      INSERT INTO content_modules (uid, name, namespace, help_text, class, code, sequence, inserted_at, updated_at)
      VALUES ('legacy', '{"en": "Legacy Content Wrapper"}', '{"en": "migration"}', '{}', 'legacy-content',
              '{% ref refs.content %}', 999, now(), now())
      RETURNING id
      """)

    id
  end

  defp block!(module_id) do
    [[id]] =
      rows(
        "INSERT INTO content_blocks (uid, type, module_id, active, collapsed, inserted_at, updated_at) VALUES ($1, 'module', $2, true, false, now(), now()) RETURNING id",
        [Brando.Utils.generate_uid(), module_id]
      )

    id
  end

  defp ref!(owner, data) do
    {column, id} = owner

    [[ref_id]] =
      rows(
        "INSERT INTO content_refs (name, uid, data, #{column}, inserted_at, updated_at) VALUES ('content', $1, $2, $3, now(), now()) RETURNING id",
        [Brando.Utils.generate_uid(), data, id]
      )

    ref_id
  end

  defp data(ref_id), do: rows("SELECT data FROM content_refs WHERE id = $1", [ref_id]) |> hd() |> hd()

  defp up(migration),
    do: Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

  test "gives the wrapper's text refs the text editor's extensions, and leaves the others alone", %{migration: migration} do
    wrapper = wrapper!()
    template = ref!({"module_id", wrapper}, %{"type" => "text", "data" => %{"text" => "", "type" => "paragraph"}})
    text = ref!({"block_id", block!(wrapper)}, %{"type" => "text", "data" => %{"text" => "<p>Om oss</p>"}})
    picture = %{"type" => "picture", "data" => %{"path" => "images/site/a.jpg", "alt" => "Fasaden"}}
    picture_ref = ref!({"block_id", block!(wrapper)}, picture)
    html = %{"type" => "html", "data" => %{"text" => "<iframe></iframe>", "params" => [], "values" => %{}}}
    html_ref = ref!({"block_id", block!(wrapper)}, html)
    comment = %{"type" => "comment", "data" => %{"text" => "Bytt bilde i mai"}}
    comment_ref = ref!({"block_id", block!(wrapper)}, comment)

    up(migration)
    # A site may run its copy again
    up(migration)

    assert data(template)["data"]["extensions"] == @extensions
    assert data(text)["data"] == %{"text" => "<p>Om oss</p>", "extensions" => @extensions}
    assert data(picture_ref) == picture
    assert data(html_ref) == html
    assert data(comment_ref) == comment
  end
end
