defmodule Brando.I18nTest do
  use ExUnit.Case, async: true
  alias Brando.I18n

  test "get_language" do
    mock_conn = %{assigns: %{}}
    assert I18n.get_language(mock_conn) == Brando.config(:default_admin_language)
    mock_conn = %{assigns: %{language: "en"}}
    assert I18n.get_language(mock_conn) == "en"
  end

  test "extract" do
    assert I18n.parse_path([]) == {"no", ["index"]}
    assert I18n.parse_path(["en"]) == {"en", ["index"]}
    assert I18n.parse_path(["test"]) == {"no", ["test"]}
    assert I18n.parse_path(["no", "test"]) == {"no", ["test"]}
    assert I18n.parse_path(["en", "test"]) == {"en", ["test"]}
  end
end
