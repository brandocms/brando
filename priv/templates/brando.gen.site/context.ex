defmodule <%= web_module %>.CMS.SiteContext do
  use Plug.Builder

  import Brando.Plug.I18n, only: [put_locale: 2]

  plug Brando.Plug.Tenant
  plug :put_locale
  plug Brando.Plug.Identity
end
