defmodule BrandoAdmin.Components.Form.VisibilityTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.Visibility

  defp form(params) do
    types = %{kind: :string, title: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Phoenix.Component.to_form(as: :link)
  end

  test "no options: shown" do
    refute Visibility.hidden?([], form(%{}))
    refute Visibility.hidden?(nil, form(%{}))
  end

  test "hidden: true / false / a function of the form" do
    assert Visibility.hidden?([hidden: true], form(%{}))
    refute Visibility.hidden?([hidden: false], form(%{}))
    assert Visibility.hidden?([hidden: &(&1[:kind].value == "pdf")], form(%{"kind" => "pdf"}))
    refute Visibility.hidden?([hidden: fn _ -> raise "boom" end], form(%{}))
  end

  test "hidden: {field, value or values}" do
    assert Visibility.hidden?([hidden: {:kind, :pdf}], form(%{"kind" => "pdf"}))
    refute Visibility.hidden?([hidden: {:kind, :pdf}], form(%{"kind" => "url"}))
    assert Visibility.hidden?([hidden: {:kind, [:pdf, :audio]}], form(%{"kind" => "audio"}))
  end

  test "show_if: {field, value or values} shows only while the field matches" do
    opts = [show_if: {:kind, [:pdf, :audio]}]

    refute Visibility.hidden?(opts, form(%{"kind" => "pdf"}))
    refute Visibility.hidden?(opts, form(%{"kind" => "audio"}))
    assert Visibility.hidden?(opts, form(%{"kind" => "url"}))
    assert Visibility.hidden?(opts, form(%{}))
  end
end
