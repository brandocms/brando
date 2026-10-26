defmodule Brando.Security.NoAtomsFromInputTest do
  # Atoms are never freed and the table has a fixed size: when it is full the
  # node stops. Names that arrive in a request or in stored content are
  # looked up among the atoms that exist, never turned into new ones.
  use ExUnit.Case, async: true

  alias Brando.I18n.Helpers
  alias Brando.Query
  alias Brando.SyncTest.Article

  defp fresh, do: "zz_no_atom_#{System.unique_integer([:positive])}"

  defp atom?(string) do
    _ = String.to_existing_atom(string)
    true
  rescue
    ArgumentError -> false
  end

  describe "an order from the URL" do
    test "resolves to the schema's fields and associations" do
      assert Query.resolve_order("desc title", Article) == {:ok, [{:desc, :title}]}

      assert Query.resolve_order("asc parent.title, desc_nulls_last id", Article) ==
               {:ok, [{:asc, {:parent, :title}}, {:desc_nulls_last, :id}]}

      assert Query.resolve_order(%{"asc" => "title"}, Article) == {:ok, [{:asc, :title}]}
      assert Query.resolve_order("asc random", Article) == {:ok, [{:asc, :random}]}
    end

    test "is refused as a whole when any part is unknown, and makes no atom" do
      for order <- [
            "asc #{fresh()}",
            "#{fresh()} title",
            "asc parent.#{fresh()}",
            "asc #{fresh()}.#{fresh()}.#{fresh()}",
            "asc title, desc #{fresh()}",
            "asc title id",
            "",
            %{"asc" => fresh()},
            %{fresh() => "title"}
          ] do
        assert Query.resolve_order(order, Article) == :error, inspect(order)

        names = if is_map(order), do: Enum.flat_map(order, &Tuple.to_list/1), else: String.split(order, ~r/[ ,.]/)
        refute Enum.any?(names, &(String.starts_with?(&1, "zz_no_atom_") and atom?(&1)))
      end

      # A field of an associated schema, not the listed one
      assert Query.resolve_order("asc parent.parent.parent.title", Article) == :error
      assert Query.resolve_order(["asc title"], Article) == :error
    end
  end

  test "a Blueprint name from an event or a stored row" do
    assert Brando.Blueprint.from_name("Brando.SyncTest.Article") == Article
    assert Brando.Blueprint.from_name("Elixir.Brando.SyncTest.Article") == Article
    # A module, but no Blueprint
    assert Brando.Blueprint.from_name("Brando.Utils") == nil

    name = fresh()
    assert Brando.Blueprint.from_name("Brando.#{name}") == nil
    assert BrandoAdmin.Components.Activity.schema("Brando.#{name}") == nil
    refute atom?("Elixir.Brando.#{name}")
  end

  test "a module name a form sends back casts only when the module exists" do
    assert Brando.Type.Module.cast("Brando.SyncTest.Article") == {:ok, Article}
    name = fresh()
    assert Brando.Type.Module.cast("Brando.#{name}") == :error
    refute atom?("Elixir.Brando.#{name}")
  end

  describe "a template's route tags" do
    test "name helpers and actions that exist, and make no atom of the others" do
      for {tpl, name} <- [{"{% route NAME index %}", fresh()}, {"{% route project_path NAME %}", fresh()}] do
        {:ok, parsed} = Liquex.parse(String.replace(tpl, "NAME", name), Brando.Villain.LiquexParser)

        assert_raise ArgumentError, fn ->
          Liquex.Render.render!([], parsed, Brando.Villain.get_base_context())
        end

        refute atom?(name)
      end
    end

    test "with a locale from content make no atom of it" do
      locale = fresh()
      assert Helpers.localized_path(locale, :project_path, [Brando.endpoint(), :index]) =~ "/"
      refute atom?("#{locale}_project_path")

      fun = fresh()
      assert Helpers.localized_path("no", fun, [Brando.endpoint(), :index]) == "/<url cannot be localized>"
      refute atom?(fun)
      refute atom?("no_#{fun}")
    end
  end
end
