defmodule Brando.DatasourcesTest do
  use ExUnit.Case, async: true

  defmodule TestDatasource do
    use Brando.Datasource

    datasources do
      many :all, fn module, _ ->
        {:ok, module}
      end

      many :all_more, fn _, arg ->
        {:ok, arg}
      end

      selection :featured,
                fn _, _ ->
                  {:ok,
                   [
                     %{id: 1, label: "The first entry"},
                     %{id: 2, label: "The second entry"},
                     %{id: 3, label: "The third entry"}
                   ]}
                end,
                fn _, ids ->
                  all = [
                    %{id: 1, name: "The actual entry"},
                    %{id: 2, name: "The actual entry 2"},
                    %{id: 3, name: "The actual entry 3"}
                  ]

                  {:ok, Enum.filter(all, &(&1.id in ids)) |> Enum.reverse()}
                end
    end
  end

  alias Brando.DatasourcesTest.TestDatasource

  test "__datasources__" do
    assert TestDatasource.__datasources__(:many) == [:all_more, :all]
  end

  test "list datasources" do
    assert Brando.Datasource.list_datasources() == {:ok, []}
  end

  test "list datasource keys" do
    assert Brando.Datasource.list_datasource_keys(TestDatasource) ==
             {:ok, %{many: [:all_more, :all], one: [], selection: [:featured]}}
  end

  test "get_many" do
    assert Brando.Datasource.get_many(TestDatasource, "all", nil) == {:ok, TestDatasource}
    assert Brando.Datasource.get_many(TestDatasource, "all_more", "argument") == {:ok, "argument"}
  end

  test "list_selection" do
    list_result =
      {:ok,
       [
         %{id: 1, label: "The first entry"},
         %{id: 2, label: "The second entry"},
         %{id: 3, label: "The third entry"}
       ]}

    assert Brando.Datasource.list_selection(TestDatasource, "featured", nil) == list_result
  end

  test "get_selection" do
    get_result =
      {:ok,
       [
         %{id: 3, name: "The actual entry 3"},
         %{id: 1, name: "The actual entry"}
       ]}

    assert Brando.Datasource.get_selection(TestDatasource, "featured", [3, 1]) == get_result
  end
end
