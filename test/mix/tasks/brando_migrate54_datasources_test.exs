defmodule Mix.Tasks.Brando.Migrate54DatasourcesTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @path "lib/lett/team/member.ex"

  # koi's 0.53 Team.Member: a list and a selection both named :all, and a
  # `from` that relied on `use Brando.Datasource` importing Ecto.Query.
  @member """
  defmodule Lett.Team.Member do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Team",
      schema: "Member",
      singular: "member",
      plural: "members"

    use Brando.Datasource
    import LettAdmin.Gettext
    alias Lett.Team

    identifier "{{ entry.name }} [{{ entry.language }}]"

    datasources do
      list :all, fn _, language, _ ->
        Team.list_members(%{
          filter: %{language: language},
          status: :published,
          order: [{:asc, :sequence}],
          preload: [:cover]
        })
      end

      selection :all,
                fn module, language, _ ->
                  {:ok,
                   Brando.Content.list_identifiers(module, %{
                     language: language,
                     order: "asc language, asc entry_id",
                     status: :published
                   })}
                end,
                fn identifiers ->
                  entry_ids = Enum.map(identifiers, & &1.entry_id)

                  results =
                    from t in Team.Member,
                      where: t.id in ^entry_ids,
                      order_by: fragment("array_position(?, ?)", ^entry_ids, t.id)

                  {:ok, Lett.Repo.all(results)}
                end
    end
  end
  """

  test "renames the selection that shares the list's name, and lists it" do
    igniter = migrate(@member)
    blueprint = source(igniter, @path)

    assert blueprint =~ "datasource(:all) do\n      type(:list)"
    assert blueprint =~ "datasource(:all_selection) do\n      type(:selection)"
    assert count(blueprint, "datasource(:all)") == 1

    assert_has_notice(igniter, fn notice ->
      notice =~ "declared more than once" and
        notice =~ "#{@path}:25: Lett.Team.Member `selection :all` is now :all_selection" and
        notice =~ "choose the new name"
    end)

    rerun = igniter |> apply_igniter!() |> Igniter.include_existing_file(@path) |> Migrate54.igniter()
    assert_unchanged(rerun, @path)
  end

  test "keeps Ecto.Query's macros imported when it removes `use Brando.Datasource`" do
    blueprint = @member |> migrate() |> source(@path)

    refute blueprint =~ "use Brando.Datasource"
    assert blueprint =~ "import Ecto.Query, only: [from: 2]"
  end

  test "imports nothing for a module that does not build queries" do
    member =
      @member
      |> String.replace(~r/\n    selection :all,.*?end\n(?=  end\n)/s, "\n")

    blueprint = member |> migrate() |> source(@path)

    refute blueprint =~ "use Brando.Datasource"
    refute blueprint =~ "Ecto.Query"
    refute blueprint =~ "all_selection"
  end

  defp migrate(blueprint) do
    [app_name: :lett, files: %{@path => blueprint}]
    |> test_project()
    |> Igniter.include_existing_file(@path)
    |> Migrate54.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp count(content, pattern), do: content |> String.split(pattern) |> length() |> Kernel.-(1)
end
