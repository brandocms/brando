defmodule <%= web_module %>.CMS.LockdownHTML do
  use BrandoWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={assigns[:language] || Brando.config(:default_language)}>
      <.head conn={@conn}>
        <:title>{gettext("Coming soon")}</:title>
        <meta name="robots" content="noindex" />
      </.head>
      <.body_tag conn={@conn} id="lockdown">
        {@inner_content}
      </.body_tag>
    </html>
    """
  end

  def index(assigns) do
    ~H"""
    <main id="content" class="lockdown">
      <h1>{gettext("Coming soon")}</h1>
      <form :if={@password?} action={@action} method="post">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <label for="lockdown-password">{gettext("Password")}</label>
        <input id="lockdown-password" name="password" type="password" autocomplete="current-password" required />
        <p :if={@failed?} role="alert">{gettext("That password is not right.")}</p>
        <button type="submit">{gettext("Enter")}</button>
      </form>
    </main>
    """
  end
end
