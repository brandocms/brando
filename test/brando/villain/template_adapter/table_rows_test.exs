defmodule Brando.Villain.TemplateAdapter.TableRowsTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Module, as: ContentModule
  alias Brando.Content.TableRow
  alias Brando.Content.Var
  alias Brando.Villain.TemplateAdapter.Heex
  alias Brando.Villain.TemplateAdapter.Liquex, as: LiquexAdapter

  defp module(type, code) do
    %ContentModule{
      id: System.unique_integer([:positive]),
      type: type,
      class: "table-rows-test",
      code: code,
      datasource: false
    }
  end

  defp block do
    rows =
      for {city, sequence} <- Enum.with_index(["Oslo", "Bergen"]) do
        %TableRow{
          sequence: sequence,
          vars: [
            %Var{type: :string, key: "city", label: "City", value: city},
            %Var{type: :boolean, key: "open", label: "Open", value_boolean: sequence == 0}
          ]
        }
      end

    %{
      active: true,
      anchor: nil,
      block_identifiers: [],
      collapsed: false,
      description: nil,
      module_id: 123,
      refs: [],
      sequence: 0,
      table_rows: rows,
      type: :module,
      uid: "table-rows-test-block",
      vars: []
    }
  end

  defp opts, do: %{context: Liquex.Context.new(%{}), parser_module: Brando.Villain.Parser}

  test "Liquid templates read table row vars by key and by position" do
    code = """
    {% for row in block.table_rows %}<li data-open="{{ row.open }}">{{ row.city }}|{{ row.vars[0].value }}</li>{% endfor %}
    """

    html = LiquexAdapter.render_module(module(:liquid, code), block(), %{}, %{}, opts())

    assert html =~ ~s(<li data-open="true">Oslo|Oslo</li>)
    assert html =~ ~s(<li data-open="false">Bergen|Bergen</li>)
  end

  test "HEEx templates read table row vars by key and by position" do
    code = """
    <ul><li :for={row <- @block.table_rows}>{row.city}|{hd(row.vars).value}</li></ul>
    """

    html = Heex.render_module(module(:heex, code), block(), %{}, %{}, opts())

    assert html =~ "<li>Oslo|Oslo</li>"
    assert html =~ "<li>Bergen|Bergen</li>"
  end
end
