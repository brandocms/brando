defmodule Brando.Migrations.UpgradeFromVillainCheckTest do
  # A pre-blocks site taken through every later upgrade template
  # (Brando.UpgradeFromVillainCase, which has the setup and helpers):
  # `mix brando.check.legacy_conversion` on it.
  use Brando.UpgradeFromVillainCase

  alias Brando.Migration.LegacyConversion

  describe "mix brando.check.legacy_conversion" do
    test "finds the Villain content in the converted blocks, and lists what they have beyond it" do
      load_schema()
      %{contact: contact_id} = insert_villain_site()
      Enum.each(templates(103..1000), &migrate/1)

      assert {:ok, report} = LegacyConversion.check("public")
      assert report.findings == []
      assert report.dropped == []

      assert report.sources == [
               %{table: "content_templates", column: "data", join_table: "content_templates_blocks", entries: 0},
               %{table: "pages", column: "data", join_table: "pages_blocks", entries: 2},
               %{table: "pages_fragments", column: "data", join_table: "pages_fragments_blocks", entries: 1}
             ]

      assert {nil, ["Comparing Villain content with its blocks in public\n" | output]} = run_check([])

      assert last_line(output) =~
               "Checked 3 entries (content_templates.data, pages.data, pages_fragments.data): every Villain block"

      # A table row an editor added since
      video_block = contact_id |> root_block(0) |> child_block(1)

      rows(
        "INSERT INTO content_table_rows (block_id, sequence, inserted_at, updated_at) VALUES ($1, 2, now(), now())",
        [video_block]
      )

      assert findings() == [
               {:extra,
                ~s|pages ##{contact_id} › block 1 (container) › block 2 (module "Video") › table rows: 2 in Villain, 3 now|}
             ]

      assert {nil, output} = run_check([])
      assert last_line(output) =~ "nothing missing, 1 beyond Villain's (fails with --strict)"
      assert {{:exit, {:shutdown, 1}}, _output} = run_check(["--strict"])
    end

    test "names the refs and fragment_id the converted blocks lost" do
      load_schema()
      %{page: page_id, fragment: fragment_id} = insert_villain_site()
      Enum.each(templates(103..1000), &migrate/1)

      first_entry = page_id |> root_block(2) |> child_block(0)
      rows("DELETE FROM content_refs WHERE block_id = $1 AND name = 'p'", [first_entry])
      rows("UPDATE content_blocks SET fragment_id = NULL WHERE type = 'fragment'")

      expected = [
        "pages ##{page_id} › block 1 (fragment) › fragment_id: #{fragment_id} in Villain, none now",
        ~s|pages ##{page_id} › block 3 (module "Values") › entry 1 › refs: p missing|
      ]

      assert findings() == Enum.map(expected, &{:missing, &1})

      assert {{:exit, {:shutdown, 1}}, output} = run_check([])
      assert Enum.map(expected, &("  " <> &1)) -- output == []

      assert last_line(output) =~
               "Checked 3 entries (content_templates.data, pages.data, pages_fragments.data): 2 missing"

      # Once a Villain column is dropped, its blocks are no longer checked
      rows("ALTER TABLE pages_fragments DROP COLUMN data")

      assert {:ok, %{dropped: [%{table: "pages_fragments", column: "data", join_table: "pages_fragments_blocks"}]}} =
               LegacyConversion.check("public")

      assert {{:exit, {:shutdown, 1}}, output} = run_check([])
      assert "  pages_fragments_blocks (pages_fragments.data)" in output
      assert last_line(output) =~ "Checked 2 entries (content_templates.data, pages.data): 2 missing"
    end

    test "finds the vars of a multi module that brando_108 dropped" do
      load_schema()
      %{page: page_id} = insert_villain_site()

      # brando_108 as it shipped before it carried a multi module's own vars
      without_multi_vars = fn source ->
        multi_vars = """
                if vars = get_in(module, ["data", "vars"]) do
                  process_vars(block_id, vars)
                end
        """

        assert source =~ multi_vars
        String.replace(source, multi_vars, "")
      end

      for path <- templates(103..1000) do
        if number(path) == 108, do: migrate(path, without_multi_vars), else: migrate(path)
      end

      assert findings() == [{:missing, ~s|pages ##{page_id} › block 3 (module "Values") › vars: heading missing|}]
    end
  end
end
