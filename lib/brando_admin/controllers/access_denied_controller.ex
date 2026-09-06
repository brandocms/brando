defmodule BrandoAdmin.AccessDeniedController do
  use BrandoAdmin, :controller

  def show(conn, _params) do
    conn
    |> put_status(:forbidden)
    |> html("""
    <!doctype html><html lang="en"><meta name="viewport" content="width=device-width">
    <title>Access unavailable · Brando</title>
    <main style="max-width:36rem;margin:15vh auto;padding:2rem;font:1.1rem/1.6 system-ui;color:#262b29">
      <p>BRANDO / ACCESS</p><h1>This area isn’t available to you.</h1>
      <p>Your permissions may have changed. Ask an administrator to review your groups for this site.</p>
      <p><a href="/admin">Return to your workspace</a> · <a href="/admin/logout">Sign out</a></p>
    </main></html>
    """)
  end
end
