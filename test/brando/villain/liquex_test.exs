defmodule Brando.Villain.LiquexTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  test "if statement" do
    Brando.Cache.Globals.set()

    global_category_params = %{
      "label" => "System",
      "key" => "system",
      "globals" => [
        %{type: "text", label: "Text", key: "text", data: %{"value" => "My text"}},
        %{type: "boolean", label: "Text", key: "boolean", data: %{"value" => false}}
      ]
    }

    {:ok, _gc1} = Brando.Globals.create_global_category(global_category_params)

    context = Brando.Villain.get_base_context()

    html =
      """
      {% if globals.system.text == "My text" %}
        Matches!
      {% endif %}
      """
      |> String.trim()
      |> Brando.Villain.parse_and_render(context)

    assert html == "\n  Matches!\n"

    html =
      """
      {% if globals.system.boolean %}
        Matches!
      {% else %}
        Boolean is false
      {% endif %}
      """
      |> String.trim()
      |> Brando.Villain.parse_and_render(context)

    assert html == "\n  Boolean is false\n"
  end
end
