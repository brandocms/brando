defmodule Brando.Pages.FragmentKeyWarningTest do
  use ExUnit.Case, async: true

  alias Brando.Pages.Fragment

  defp form(fragment, params) do
    fragment
    |> Ecto.Changeset.cast(params, [:parent_key, :key, :title])
    |> Phoenix.Component.to_form()
  end

  test "warns while a saved fragment's key or parent key is being changed" do
    saved = %Fragment{id: 1, parent_key: "partials", key: "footer"}

    assert Fragment.key_changed?(form(saved, %{"key" => "site-footer"}))
    assert Fragment.key_changed?(form(saved, %{"parent_key" => "parts"}))
    refute Fragment.key_changed?(form(saved, %{"title" => "Footer"}))
  end

  test "a new fragment's keys are free to set" do
    refute Fragment.key_changed?(form(%Fragment{}, %{"key" => "footer"}))
  end

  test "the form has the alert, shown only by that check" do
    [form] = Spark.Dsl.Extension.get_entities(Fragment, [:forms])
    alerts = Enum.flat_map(form.tabs, & &1.alerts)

    assert [%{type: :warning, show_if: show_if}] = alerts
    assert show_if == (&Fragment.key_changed?/1)
  end

  test "tab alerts are kept (they used to be dropped)" do
    password_form =
      Brando.Users.User
      |> Spark.Dsl.Extension.get_entities([:forms])
      |> Enum.find(&(&1.name == :password))

    assert [%Brando.Blueprint.Forms.Alert{type: :info}] = Enum.flat_map(password_form.tabs, & &1.alerts)
  end
end
