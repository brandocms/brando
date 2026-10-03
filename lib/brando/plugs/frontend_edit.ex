defmodule Brando.Plug.FrontendEdit do
  @moduledoc """
  Frontend edit mode for signed-in admins. See `Brando.FrontendEdit` for the
  feature; add this plug to the browser pipeline after the session is
  fetched:

      plug Brando.Plug.FrontendEdit

  For an admin it adds an "Edit page" button to HTML pages. With edit mode
  on (a cookie the button sets), it renders the page's blocks with markers,
  adds the editing overlay and a manifest of what can be edited, and marks
  the response `private, no-store` so no cache keeps the annotated page.
  Requests from anyone else pass through untouched.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Brando.Authorization.Engine
  alias Brando.FrontendEdit
  alias Brando.FrontendEdit.Manifest

  @external_resource Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/block_patch.js")
  @external_resource Application.app_dir(:brando, "priv/static/js/frontend_edit.js")
  @external_resource Application.app_dir(:brando, "priv/static/css/frontend_edit.css")

  @morphdom_js File.read!(Application.app_dir(:brando, "priv/static/js/morphdom-umd.min.js"))
  @block_patch_js File.read!(Application.app_dir(:brando, "priv/static/js/block_patch.js"))
  @frontend_edit_js File.read!(Application.app_dir(:brando, "priv/static/js/frontend_edit.js"))
  @frontend_edit_css File.read!(Application.app_dir(:brando, "priv/static/css/frontend_edit.css"))

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    # A connection process serves its keep-alive requests one after another;
    # never let one request's edit mode reach the next.
    FrontendEdit.deactivate()

    with true <- FrontendEdit.enabled?(),
         true <- conn.method == "GET",
         false <- Map.get(conn.private, :brando_live_preview, false),
         false <- internal_route?(conn),
         {:ok, conn} <- with_session(conn),
         %{} = user <- admin_user(conn) do
      conn = fetch_cookies(conn)
      active? = conn.cookies[FrontendEdit.cookie()] == "1"

      if active?, do: FrontendEdit.activate()

      conn
      |> put_private(:brando_frontend_edit, %{user: user, active?: active?})
      |> register_before_send(&inject/1)
    else
      _ -> conn
    end
  end

  # Brando's own routes (`/__p__/…` shared previews, `/__ssg_preview__/…`,
  # `/__brando/…`) serve snapshots and endpoints, not pages to edit.
  defp internal_route?(%{path_info: ["__" <> _ | _]}), do: true
  defp internal_route?(_conn), do: false

  # A pipeline without a session has no admins to recognize.
  defp with_session(%{private: %{plug_session: _}} = conn), do: {:ok, conn}
  defp with_session(%{private: %{plug_session_fetch: _}} = conn), do: {:ok, fetch_session(conn)}
  defp with_session(_conn), do: :error

  defp admin_user(conn) do
    with token when is_binary(token) <- get_session(conn, :user_token),
         %Brando.Users.User{} = user <- Brando.Users.get_user_by_session_token(token),
         true <- backend_access?(user) do
      user
    else
      _ -> nil
    end
  end

  defp backend_access?(user), do: not Engine.enabled?() or Engine.backend_access?(user)

  @doc false
  def inject(%{private: %{brando_frontend_edit: %{user: user, active?: active?}}} = conn) do
    FrontendEdit.deactivate()

    if html_response?(conn) do
      body = IO.iodata_to_binary(conn.resp_body)

      case String.split(body, "</body>", parts: 2) do
        [page, rest] ->
          conn
          |> put_resp_header("cache-control", "private, no-store")
          |> Map.put(:resp_body, [page, inject_html(body, user, active?), "</body>", rest])

        [_] ->
          conn
      end
    else
      conn
    end
  rescue
    error ->
      Logger.error(
        "==> FrontendEdit: could not add the editor to the page.\n" <> Exception.format(:error, error, __STACKTRACE__)
      )

      conn
  end

  def inject(conn), do: conn

  defp html_response?(%{status: 200, resp_body: body} = conn) when not is_nil(body) do
    case get_resp_header(conn, "content-type") do
      [type | _] -> String.starts_with?(type, "text/html")
      [] -> false
    end
  end

  defp html_response?(_), do: false

  defp inject_html(body, user, active?) do
    locale = Gettext.get_locale(Brando.Gettext)
    Gettext.put_locale(Brando.Gettext, to_string(user.language || locale))

    try do
      config = %{
        active: active?,
        cookie: FrontendEdit.cookie(),
        editorUrl: editor_path(),
        adminUrl: admin_path(),
        user: %{id: user.id, name: user.name},
        manifest: if(active?, do: Manifest.build(body, user), else: nil),
        text: FrontendEdit.Text.strings()
      }

      [
        "\n<!-- BRANDO FRONTEND EDIT -->\n",
        ~s(<script type="application/json" id="brando-frontend-edit-config">),
        Jason.encode!(config, escape: :html_safe),
        "</script>\n<script>\n",
        if(active?, do: [@morphdom_js, "\n", @block_patch_js, "\n"], else: []),
        "window.BrandoFrontendEditCSS = ",
        Jason.encode!(@frontend_edit_css, escape: :html_safe),
        ";\n",
        @frontend_edit_js,
        "\n</script>\n"
      ]
    after
      Gettext.put_locale(Brando.Gettext, locale)
    end
  end

  @doc "Where the editor sidebar's admin view is mounted."
  def editor_path, do: admin_path() <> "/frontend-edit"

  # The admin is mounted at `/admin` (`Brando.Router.admin_routes/2`), as the
  # live preview's socket and the assistant links also assume.
  defp admin_path, do: "/admin"
end
