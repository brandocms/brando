defmodule Brando.I18n.HelpersTest do
  use ExUnit.Case, async: true
  import Brando.I18n.Helpers

  setup do
    # Mock config values that are used by the functions
    original_default_language = Application.get_env(:brando, :default_language)
    original_scope_routes = Application.get_env(:brando, :scope_default_language_routes)
    original_helpers_module = Application.get_env(:brando, :helpers_module)

    Application.put_env(:brando, :default_language, "en")
    Application.put_env(:brando, :scope_default_language_routes, false)
    Application.put_env(:brando, :helpers_module, BrandoIntegrationWeb.Router.Helpers)

    # Create a mocked conn with locale
    mock_conn =
      %Plug.Conn{}
      |> Brando.Plug.I18n.put_locale(skip_session: true)

    on_exit(fn ->
      # Restore the original config
      if original_default_language != nil do
        Application.put_env(:brando, :default_language, original_default_language)
      else
        Application.delete_env(:brando, :default_language)
      end

      if original_scope_routes != nil do
        Application.put_env(:brando, :scope_default_language_routes, original_scope_routes)
      else
        Application.delete_env(:brando, :scope_default_language_routes)
      end

      if original_helpers_module != nil do
        Application.put_env(:brando, :helpers_module, original_helpers_module)
      else
        Application.delete_env(:brando, :helpers_module)
      end
    end)

    {:ok, conn: mock_conn}
  end

  test "localized_path with default language (no scoping)", %{conn: mock_conn} do
    # When using the default language and scoping is false
    assert localized_path("en", :project_path, [mock_conn, :index]) == "/projects"
    assert localized_path("en", :project_path, [mock_conn, :show, 123]) == "/project/123"

    # Test with atom locale
    assert localized_path(:en, :project_path, [mock_conn, :index]) == "/projects"
  end

  test "localized_path with non-default language", %{conn: mock_conn} do
    # When using a non-default language
    assert localized_path("no", :project_path, [mock_conn, :index]) == "/no/prosjekter"
    assert localized_path("no", :project_path, [mock_conn, :show, 123]) == "/no/prosjekt/123"

    # Test with atom locale
    assert localized_path(:no, :project_path, [mock_conn, :index]) == "/no/prosjekter"
  end

  test "localized_path with scoped default language", %{conn: mock_conn} do
    # Change config to scope default language
    Application.put_env(:brando, :scope_default_language_routes, true)

    # Now even the default language should use the localized path
    assert localized_path("en", :project_path, [mock_conn, :scoped_index]) == "/en/projects"
    assert localized_path("en", :project_path, [mock_conn, :scoped_show, 123]) == "/en/project/123"
  end

  test "localized_path with missing localized function", %{conn: mock_conn} do
    # Test behavior with a language that doesn't have its own path function
    assert localized_path("fr", :project_path, [mock_conn, :index]) == "/projects"
    assert localized_path("fr", :project_path, [mock_conn, :show, 123]) == "/project/123"
  end

  test "localized_path with non-existent function", %{conn: mock_conn} do
    # Test behavior with a function that doesn't exist
    assert localized_path("en", :nonexistent_path, [mock_conn, :index]) == "/<url cannot be localized>"
  end

  test "handles atom default_language in config", %{conn: mock_conn} do
    # Test with atom in default_language config
    Application.put_env(:brando, :default_language, :en)
    assert localized_path("en", :project_path, [mock_conn, :index]) == "/projects"
    assert localized_path("no", :project_path, [mock_conn, :index]) == "/no/prosjekter"
  end

  test "page path", %{conn: mock_conn} do
    Application.put_env(:brando, :default_language, "en")
    assert localized_path("en", :page_path, [mock_conn, :index]) == "/"
    assert localized_path("en", :page_path, [mock_conn, :show, ["about"]]) == "/about"
    # since we have `page_routes` at the scope "/", we pass language as arg for page_path
    refute localized_path("no", :page_path, [mock_conn, :show, ["om"]]) == "/no/om"
    assert localized_path("no", :page_path, [mock_conn, :show, ["no", "om"]]) == "/no/om"
  end
end
