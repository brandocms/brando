defmodule Brando.I18nTest do
  use ExUnit.Case, async: true

  test "get_language" do
    mock_conn = %{assigns: %{}}
    Brando.I18n.get_language(mock_conn) == "nb"
    mock_conn = %{assigns: %{language: "en"}}
    Brando.I18n.get_language(mock_conn) == "en"
  end
end
