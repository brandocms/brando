defmodule BrandoAdmin.AccessDeniedController do
  use BrandoAdmin, :controller
  use Gettext, backend: Brando.Gettext
  import Phoenix.Component, only: [sigil_H: 2]

  def show(conn, _params) do
    # Signing out is a DELETE with the CSRF token: GET /admin/logout only asks
    assigns = %{locale: Gettext.get_locale(Brando.Gettext), csrf_token: get_csrf_token()}

    page = ~H"""
    <!doctype html><html lang={@locale}>
      <meta name="viewport" content="width=device-width" />
      <title>{gettext("Access unavailable")} · Brando</title>
      <main style="max-width:36rem;margin:15vh auto;padding:2rem;font:1.1rem/1.6 system-ui;color:#262b29">
        <p>BRANDO / {gettext("ACCESS")}</p><h1>{gettext("This area isn’t available to you.")}</h1>
        <p>{gettext("Your permissions may have changed. Ask an administrator to review your groups for this site.")}</p>
        <form method="post" action="/admin/logout">
          <input type="hidden" name="_method" value="delete" />
          <input type="hidden" name="_csrf_token" value={@csrf_token} />
          <a href="/admin">{gettext("Return to your workspace")}</a>
          ·
          <button
            type="submit"
            style="padding:0;border:0;background:none;font:inherit;color:LinkText;text-decoration:underline;cursor:pointer"
          >
            {gettext("Sign out")}
          </button>
        </form>
      </main>
    </html>
    """

    conn
    |> put_status(:forbidden)
    |> html(Phoenix.HTML.Safe.to_iodata(page))
  end
end
