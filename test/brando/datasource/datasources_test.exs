defmodule Brando.DatasourcesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  alias Brando.Factory

  defmodule TestDatasource do
    use Brando.Datasource

    datasources do
      list(:all, fn module, _ ->
        {:ok, module}
      end)

      list(:all_of_them, fn _, _ ->
        {:ok, [%{id: 1, name: "1"}, %{id: 2, name: "2"}, %{id: 3, name: "3"}]}
      end)

      list(:all_more, fn _, arg ->
        {:ok, arg}
      end)

      single(:single, fn module, _ ->
        {:ok, module}
      end)

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
    assert TestDatasource.__datasources__(:list) == [:all_more, :all_of_them, :all]
  end

  test "list datasources" do
    assert Brando.Datasource.list_datasources() == {:ok, []}
  end

  test "list datasource keys" do
    assert Brando.Datasource.list_datasource_keys(TestDatasource) ==
             {:ok, %{list: [:all_more, :all_of_them, :all], single: [], selection: [:featured]}}
  end

  test "get_list" do
    assert Brando.Datasource.get_list(TestDatasource, "all", nil) == {:ok, TestDatasource}
    assert Brando.Datasource.get_list(TestDatasource, "all_more", "argument") == {:ok, "argument"}
  end

  test "get_single" do
    assert Brando.Datasource.get_single(TestDatasource, "single", nil) == {:ok, TestDatasource}
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

  test "update_datasource" do
    data = [
      %{
        "type" => "datasource",
        "data" => %{
          "module" => "Elixir.Brando.DatasourcesTest.TestDatasource",
          "type" => "list",
          "query" => "all_of_them",
          "code" => """
          {% for entry in entries %}
          <li>{{ entry.name }}</li>
          {% endfor %}
          """
        }
      }
    ]

    page_params = Factory.params_for(:page, data: data)
    user = Factory.insert(:random_user)
    {:ok, p1} = Brando.Pages.create_page(page_params, user)
    assert p1.html == "\n<li>1</li>\n\n<li>2</li>\n\n<li>3</li>\n\n"

    assert Brando.Datasource.update_datasource(TestDatasource, :pass_through) ==
             {:ok, :pass_through}
  end
end
