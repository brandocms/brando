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
             {:ok, %{many: [:all_more, :all], one: []}}
  end

  test "get_many" do
    assert Brando.Datasource.get_many(TestDatasource, "all", nil) == {:ok, TestDatasource}
    assert Brando.Datasource.get_many(TestDatasource, "all_more", "argument") == {:ok, "argument"}
  end
end
