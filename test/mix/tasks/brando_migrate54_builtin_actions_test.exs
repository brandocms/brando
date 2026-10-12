defmodule Mix.Tasks.Brando.Migrate54BuiltinActionsTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @path "lib/lett/articles/category.ex"

  @category """
  defmodule Lett.Articles.Category do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Category",
      singular: "category",
      plural: "categories"

    import LettAdmin.Gettext

    listings do
      listing do
        listing_query %{
          order: [{:asc, :sequence}, {:desc, :inserted_at}]
        }

        filters([
          [label: gettext("Name"), filter: "name"]
        ])

        actions([
          [label: gettext("Edit category"), event: "edit_entry"],
          [label: gettext("Duplicate category"), event: "duplicate_entry"],
          [
            label: gettext("Delete category"),
            event: "delete_entry",
            confirm: gettext("Are you sure?")
          ],
          [label: gettext("Publish"), event: "publish_entry"]
        ])
      end
    end
  end
  """

  test "removes 0.53 actions that repeat the built-in edit, duplicate and delete" do
    igniter = migrate(@category)
    blueprint = source(igniter, @path)

    refute blueprint =~ ~r/"(edit|duplicate|delete)_entry"/
    assert blueprint =~ ~r/action\(\s*label: t\("Publish"\),\s*event: "publish_entry"\s*\)/
    refute blueprint =~ "Are you sure?"

    assert_has_notice(igniter, fn notice ->
      notice =~ "Listing actions that repeat a built-in were removed" and
        notice =~ ~s|  Lett.Articles.Category: gettext("Edit category")\n| and
        notice =~ ~s|  Lett.Articles.Category: gettext("Duplicate category")\n| and
        notice =~ ~s|  Lett.Articles.Category: gettext("Delete category")\n|
    end)

    rerun =
      igniter
      |> apply_igniter!()
      |> Igniter.include_existing_file(@path)
      |> Migrate54.igniter()

    assert_unchanged(rerun, @path)
  end

  test "removes them from action declarations an earlier run wrote" do
    rewritten = """
    defmodule Lett.Restaurants.Restaurant do
      use Brando.Blueprint,
        application: "Lett",
        domain: "Restaurants",
        schema: "Restaurant",
        singular: "restaurant",
        plural: "restaurants"

      listings do
        listing do
          action(
            label: t("Edit restaurant"),
            event: "edit_entry"
          )

          action(
            label: t("Duplicate restaurant"),
            event: "duplicate_entry"
          )

          action(
            label: t("Delete restaurant"),
            event: "delete_entry",
            confirm: t("Are you sure?")
          )
        end
      end
    end
    """

    path = "lib/lett/restaurants/restaurant.ex"
    igniter = migrate(rewritten, path)

    refute source(igniter, path) =~ "action("
    assert_has_notice(igniter, &(&1 =~ ~s|  Lett.Restaurants.Restaurant: t("Delete restaurant")|))
  end

  test "keeps them in a listing without the built-ins, and lists one with options of its own" do
    without_defaults =
      String.replace(
        @category,
        ~r/"publish_entry"\]\n(\s*)\]\)/,
        ~s|"publish_entry"]\n\\1], default_actions: false)|
      )

    blueprint = without_defaults |> migrate() |> source(@path)

    assert blueprint =~ "default_actions(false)"
    assert blueprint =~ ~r/action\(\s*label: t\("Edit category"\),\s*event: "edit_entry"\s*\)/
    assert blueprint =~ ~s|event: "delete_entry"|

    with_options =
      String.replace(
        @category,
        ~s|[label: gettext("Edit category"), event: "edit_entry"]|,
        ~s|[label: gettext("Edit category"), event: "edit_entry", visible: \&__MODULE__.editor?/1]|
      )

    igniter = migrate(with_options)

    assert source(igniter, @path) =~ ~s|event: "edit_entry"|
    refute source(igniter, @path) =~ ~s|event: "delete_entry"|

    assert_has_warning(igniter, fn warning ->
      warning =~ "have options of their own, so they were\nkept" and warning =~ "#{@path}:22: edit_entry"
    end)
  end

  defp migrate(blueprint, path \\ @path) do
    [app_name: :lett, files: %{path => blueprint}]
    |> test_project()
    |> Igniter.include_existing_file(path)
    |> Migrate54.igniter()
  end

  defp source(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end
end
