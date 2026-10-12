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

  test "keeps the list and the selection that share a name, as content modules name them" do
    igniter = migrate(@member)
    blueprint = source(igniter, @path)

    assert blueprint =~ "datasource(:all) do\n      type(:list)"
    assert blueprint =~ "datasource(:all) do\n      type(:selection)"
    refute blueprint =~ "all_selection"
    refute Enum.any?(igniter.notices, &(&1 =~ "declared more than once"))

    rerun = igniter |> apply_igniter!() |> Igniter.include_existing_file(@path) |> Migrate54.igniter()
    assert_unchanged(rerun, @path)
  end

  test "leaves a converted Blueprint's own function heads alone" do
    converted = """
    defmodule Lett.Team.Member do
      use Brando.Blueprint,
        application: "Lett",
        domain: "Team",
        schema: "Member",
        singular: "member",
        plural: "members"

      datasources do
        datasource :all do
          type :list
          list fn _module, _language, vars -> list(:all, vars) end
        end
      end

      def list(:all, vars), do: {:ok, vars}
      def selection(:all, ids, _user), do: ids
      def selection(:other, ids, _user), do: ids
    end
    """

    blueprint = converted |> migrate() |> source(@path)
    assert blueprint =~ "def selection(:all, ids, _user)"
    assert blueprint =~ "def selection(:other, ids, _user)"
  end

  test "imports Ecto.Query as `use Brando.Datasource` did when it removes the `use`" do
    blueprint = @member |> migrate() |> source(@path)

    refute blueprint =~ "use Brando.Datasource"
    assert blueprint =~ "\n  import Ecto.Query\n"
  end

  test "imports all of Ecto.Query for piped calls, and over a partial import" do
    member =
      @member
      |> String.replace(
        "  import LettAdmin.Gettext\n",
        "  import LettAdmin.Gettext\n  import Ecto.Query, only: [from: 2]\n"
      )
      |> String.replace(
        "{:ok, Lett.Repo.all(results)}",
        "{:ok, results |> where([t], t.status == :published) |> union_all(^results) |> Lett.Repo.all()}"
      )

    blueprint = member |> migrate() |> source(@path)

    assert blueprint =~ "\n  import Ecto.Query\n"
    refute blueprint =~ "only: [from: 2]"
    assert count(blueprint, "import Ecto.Query") == 1
  end

  test "imports nothing for a module that does not build queries" do
    member =
      @member
      |> String.replace(~r/\n    selection :all,.*?end\n(?=  end\n)/s, "\n")

    blueprint = member |> migrate() |> source(@path)

    refute blueprint =~ "use Brando.Datasource"
    refute blueprint =~ "Ecto.Query"
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
