defmodule Brando.I18n.HelpersTest do
  use ExUnit.Case, async: false

  import Brando.I18n.Helpers

  defmodule TestWeb.Router.Helpers do
    def fr_project_path(_endpoint), do: "/wrong-arity"
    def project_path(_endpoint, :show, id), do: "/project/#{id}"
  end

  setup do
    config_keys = [:default_language, :scope_default_language_routes, :web_module]

    original_config =
      Map.new(config_keys, fn key -> {key, Application.fetch_env(:brando, key)} end)

    Application.put_env(:brando, :default_language, "en")
    Application.put_env(:brando, :scope_default_language_routes, false)

    mock_conn =
      %Plug.Conn{}
      |> Brando.Plug.I18n.put_locale(skip_session: true)

    on_exit(fn ->
      Enum.each(original_config, fn
        {key, {:ok, value}} -> Application.put_env(:brando, key, value)
        {key, :error} -> Application.delete_env(:brando, key)
      end)
    end)

    {:ok, conn: mock_conn}
  end

  test "localized_path with default language (no scoping)", %{conn: mock_conn} do
    assert localized_path("en", :project_path, [mock_conn, :index]) == "/projects"
    assert localized_path("en", :project_path, [mock_conn, :show, 123]) == "/project/123"
    assert localized_path(:en, :project_path, [mock_conn, :index]) == "/projects"
  end

  test "localized_path with non-default language", %{conn: mock_conn} do
    assert localized_path("no", :project_path, [mock_conn, :index]) == "/no/prosjekter"
    assert localized_path("no", :project_path, [mock_conn, :show, 123]) == "/no/prosjekt/123"
    assert localized_path(:no, :project_path, [mock_conn, :index]) == "/no/prosjekter"
  end

  test "localized_path with scoped default language", %{conn: mock_conn} do
    Application.put_env(:brando, :scope_default_language_routes, true)

    assert localized_path("en", :project_path, [mock_conn, :scoped_index]) == "/en/projects"
    assert localized_path("en", :project_path, [mock_conn, :scoped_show, 123]) == "/en/project/123"
  end

  test "localized_path with missing localized function", %{conn: mock_conn} do
    assert localized_path("fr", :project_path, [mock_conn, :index]) == "/projects"
    assert localized_path("fr", :project_path, [mock_conn, :show, 123]) == "/project/123"
  end

  test "localized_path with non-existent function", %{conn: mock_conn} do
    assert localized_path("en", :nonexistent_path, [mock_conn, :index]) == "/<url cannot be localized>"
  end

  test "handles atom default_language in config", %{conn: mock_conn} do
    Application.put_env(:brando, :default_language, :en)

    assert localized_path("en", :project_path, [mock_conn, :index]) == "/projects"
    assert localized_path("no", :project_path, [mock_conn, :index]) == "/no/prosjekter"
  end

  test "falls back when a localized helper exists only at another arity" do
    Application.put_env(:brando, :web_module, TestWeb)

    assert localized_path("fr", :project_path, [:endpoint, :show, 123]) == "/project/123"
  end

  test "page path", %{conn: mock_conn} do
    Application.put_env(:brando, :default_language, "en")

    assert localized_path("en", :page_path, [mock_conn, :index]) == "/"
    assert localized_path("en", :page_path, [mock_conn, :show, ["about"]]) == "/about"
    refute localized_path("no", :page_path, [mock_conn, :show, ["om"]]) == "/no/om"
    assert localized_path("no", :page_path, [mock_conn, :show, ["no", "om"]]) == "/no/om"
  end
end
