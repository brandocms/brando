defmodule Brando.I18nTest do
  use ExUnit.Case, async: true

  test "get_language" do
    mock_conn = %{assigns: %{}}
    assert Brando.I18n.get_language(mock_conn) == nil
    mock_conn = %{assigns: %{language: "en"}}
    assert Brando.I18n.get_language(mock_conn) == "en"
  end
end
