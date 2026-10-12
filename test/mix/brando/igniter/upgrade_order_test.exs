defmodule Mix.Brando.Igniter.UpgradeOrderTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Brando.Igniter.UpgradeOrder

  @pre_blocks "priv/repo/migrations/20231121221324_brando_102_remove_legacy_entries_fields.exs"
  @current "priv/repo/migrations/20260101000218_brando_218_add_write_with_ai_to_modules.exs"
  @snapshots "priv/blueprints/snapshots/lett_articles_article"

  # A snapshot as Brando 0.53 wrote it: the Blueprint's attributes, a Villain
  # field among them.
  defp legacy_snapshot(types) do
    attributes =
      for {name, type} <- types, do: %{__struct__: Brando.Blueprint.Attribute, name: name, type: type, opts: %{}}

    :erlang.term_to_binary(%{
      __struct__: Brando.Blueprint.Snapshot,
      attributes: attributes,
      relations: [],
      assets: [],
      traits: [],
      version: 1,
      updated_at: nil
    })
  end

  defp notice(files) do
    igniter = test_project(app_name: :lett, files: files)

    # Igniter's test mode matches globs against absolute paths only.
    igniter = Enum.reduce(Map.keys(files), igniter, &Igniter.include_existing_file(&2, &1))

    {_igniter, notice} = UpgradeOrder.notice(igniter)
    notice
  end

  defp position(notice, text) do
    {index, _length} = :binary.match(notice, text)
    index
  end

  test "a newest Brando migration before the blocks conversion orders Brando's migrations first" do
    notice = notice(%{@pre_blocks => "", "priv/repo/migrations/20210101000000_brando_50_x.exs" => ""})

    assert notice =~
             "predate\nBrando's blocks conversion (the newest Brando migration in priv/repo/migrations is brando_102)"

    assert notice =~ ~s("Legacy snapshots" in\nguides/migrating_from_053.md)
    assert notice =~ "mix brando.migrations.check"

    steps = [
      "3. Run `mix brando.gen.migrations`",
      "4. Run `mix brando.migrate` on a copy of production",
      "5. Run `mix brando.check.legacy_conversion`",
      "6. Run `mix brando.gen.blueprint_migration --all --reconcile`",
      "7. Review every generated `up/0` and `down/0`, roll back and forward",
      "8. Run `mix brando.migrate` again for the Blueprint migrations",
      "9. After the database migration, run `mix brando.entries.resave`",
      "10. Run `mix brando.check.image_texts`",
      "11. Reconcile Gettext catalogs"
    ]

    positions = Enum.map(steps, &position(notice, &1))
    assert positions == Enum.sort(positions)
  end

  test "a latest snapshot with a Villain field is legacy whatever migrations were copied since" do
    notice =
      notice(%{
        @current => "",
        "#{@snapshots}/001.snapshot" => legacy_snapshot(title: :string, data: :villain),
        "#{@snapshots}/002.snapshot" => legacy_snapshot(title: :string, data: :villain, html: :text)
      })

    assert notice =~ "(the latest snapshot in #{@snapshots} has a Villain field)"
    assert notice =~ "--all --reconcile"
  end

  test "Blueprints already past the conversion, and a site on current migrations, get the generic order" do
    notice =
      notice(%{
        @current => "",
        "#{@snapshots}/001.snapshot" => legacy_snapshot(title: :string, data: :villain),
        "#{@snapshots}/002.snapshot" => legacy_snapshot(title: :string),
        "priv/blueprints/snapshots/broken/001.snapshot" => "not a term"
      })

    refute notice =~ "predate"
    refute notice =~ "--reconcile"
    assert notice =~ "mix brando.migrations.check"

    assert position(notice, "4. Run `mix brando.gen.blueprint_migration --all`") <
             position(notice, "6. Only after that review, run `mix brando.migrate`")

    assert notice =~ "9. Reconcile Gettext catalogs"
  end
end
