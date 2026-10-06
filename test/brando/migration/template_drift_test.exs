defmodule Brando.Migration.TemplateDriftTest do
  use ExUnit.Case, async: true

  alias Brando.Migration.TemplateDrift

  @moduletag :tmp_dir

  @template """
  defmodule Brando.Repo.Migrations.AddThing do
    use Ecto.Migration

    def change do
      alter table(:things) do
        add :name, :text
      end
    end
  end
  """

  setup %{tmp_dir: tmp_dir} do
    templates = Path.join(tmp_dir, "templates")
    migrations = Path.join(tmp_dir, "migrations")
    File.mkdir_p!(templates)
    File.mkdir_p!(migrations)

    File.write!(Path.join(templates, "brando_10_add_thing.exs"), @template)
    File.write!(Path.join(templates, "brando_12_fix_thing.exs"), @template)

    %{templates: templates, migrations: migrations}
  end

  defp copy(migrations, file, contents) do
    path = Path.join(migrations, file)
    File.write!(path, contents)
    path
  end

  test "a pending copy that differs as code is outdated", %{templates: templates, migrations: migrations} do
    outdated = copy(migrations, "100_brando_10_add_thing.exs", String.replace(@template, ":text", ":string"))

    assert TemplateDrift.check(migrations, MapSet.new([100]), templates) ==
             [{:outdated, outdated, Path.join(templates, "brando_10_add_thing.exs")}]
  end

  test "formatting and comments do not count", %{templates: templates, migrations: migrations} do
    reformatted =
      @template
      |> String.replace("add :name, :text", "# a comment\n      add(:name, :text)")
      |> String.replace("\n\n", "\n")

    copy(migrations, "100_brando_10_add_thing.exs", reformatted)

    assert TemplateDrift.check(migrations, MapSet.new([100]), templates) == []
  end

  test "a copy that has run is history", %{templates: templates, migrations: migrations} do
    copy(migrations, "100_brando_10_add_thing.exs", String.replace(@template, ":text", ":string"))

    assert TemplateDrift.check(migrations, MapSet.new([]), templates) == []
  end

  test "a pending copy of a renumbered template is listed", %{templates: templates, migrations: migrations} do
    renumbered = copy(migrations, "110_brando_11_fix_thing.exs", @template)
    copy(migrations, "120_site_migration.exs", @template)

    assert TemplateDrift.check(migrations, MapSet.new([110, 120]), templates) ==
             [{:renumbered, renumbered, Path.join(templates, "brando_12_fix_thing.exs")}]
  end

  test "update! replaces the copy with its template", %{templates: templates, migrations: migrations} do
    copy(migrations, "100_brando_10_add_thing.exs", "old")
    [finding] = TemplateDrift.check(migrations, MapSet.new([100]), templates)

    TemplateDrift.update!(finding)

    assert File.read!(Path.join(migrations, "100_brando_10_add_thing.exs")) == @template
    assert TemplateDrift.check(migrations, MapSet.new([100]), templates) == []
  end

  test "the real templates are found" do
    assert [_ | _] = Path.wildcard(Path.join(TemplateDrift.templates_dir(), "brando_*.exs"))
  end
end
