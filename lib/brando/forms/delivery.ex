defmodule Brando.Forms.Delivery do
  @moduledoc """
  Where a form posts, and how it is protected, for the site it is shown on.

  A dynamic site posts to `/__brando/forms/<key>` with a CSRF token; that
  route sits in the application's browser pipeline (`Brando.Router.page_routes/1`)
  and its `protect_from_forgery`. A static site (`delivery_mode: :static`) has
  no backend serving the page and no session to tie a token to, so its forms
  post to the backend's `/__brando/forms/static/<site>/<environment>/<key>`
  (`Brando.Router.form_routes/0`), where the request's origin must be one of
  the site's own domains instead.

  Block HTML is rendered when an entry is saved, so `{% form %}` cannot know the
  visitor's token. It stores the dynamic action and a `$csrftoken` placeholder
  as the value of the form's hidden `_csrf_token` input; `finalize/1` fills them
  in as the HTML is sent. Only that input is filled in: the placeholder anywhere
  else (an image URL in synced Markdown, say) stays as it is, so content cannot
  send the visitor's token to another host. A cache in front of the site
  would keep one visitor's token for everyone, so the form's script fetches a
  fresh one from `token_path/0` before it sends.

  The backend URL static forms post to defaults to the endpoint's URL:

      config :brando, Brando.Forms, submit_url: "https://admin.example.com"
  """

  alias Brando.Tenant

  @csrf_placeholder "$csrftoken"
  @dynamic_prefix "/__brando/forms/"

  # An `<input>` tag, and the attributes that make it the token input `{% form %}`
  # stores. Rendered attribute values escape their quotes, so text cannot fake
  # an attribute.
  @input_tag ~r/<input\b[^<>]*>/
  @token_name ~r/\sname\s*=\s*(["'])_csrf_token\1/
  @placeholder_value ~r/\svalue\s*=\s*(["'])\$csrftoken\1/

  @doc "The placeholder `{% form %}` stores where the CSRF token goes."
  def csrf_placeholder, do: @csrf_placeholder

  @doc "The URL a form posts to on the current site."
  def action(form_key) do
    case static_site() do
      nil -> @dynamic_prefix <> form_key
      {site_key, environment_key} -> static_action(site_key, environment_key, form_key)
    end
  end

  @doc """
  Where a form's script asks for the visitor's CSRF token before sending, in
  case the page came from a cache: `Brando.Router.page_routes/1` serves it.
  """
  def token_path, do: @dynamic_prefix <> "csrf-token"

  @doc "The token a form carries on the current site; nil on a static site."
  def csrf_token do
    if static_site(), do: nil, else: Plug.CSRFProtection.get_csrf_token()
  end

  @doc """
  Fills in what `{% form %}` left for the request: the visitor's CSRF token,
  or, on a static site, the backend action and no token.

  The token goes only into a hidden `<input name="_csrf_token">` whose whole
  value is `$csrftoken`, in any attribute order. The placeholder anywhere else
  is left as it is.
  """
  def finalize(html) when is_binary(html) do
    if String.contains?(html, @csrf_placeholder), do: do_finalize(html), else: html
  end

  def finalize(html), do: html

  defp do_finalize(html) do
    case static_site() do
      nil ->
        token = Plug.CSRFProtection.get_csrf_token()
        value = ~s( value="#{token}")
        replace_token_inputs(html, &Regex.replace(@placeholder_value, &1, fn _ -> value end))

      {site_key, environment_key} ->
        static_prefix = static_action(site_key, environment_key, "")

        html
        |> replace_token_inputs(fn _input -> "" end)
        |> String.replace("action=\"#{@dynamic_prefix}", "action=\"#{static_prefix}")
    end
  end

  defp replace_token_inputs(html, fun) do
    Regex.replace(@input_tag, html, fn input ->
      if Regex.match?(@token_name, input) and Regex.match?(@placeholder_value, input),
        do: fun.(input),
        else: input
    end)
  end

  defp static_action(site_key, environment_key, form_key),
    do: "#{submit_url()}#{@dynamic_prefix}static/#{site_key}/#{environment_key}/#{form_key}"

  # The current site and environment keys when the site is delivered statically.
  defp static_site do
    with "tenant_" <> keys <- Tenant.current_prefix(),
         [site_key, environment_key] <- String.split(keys, "_", parts: 2),
         %{delivery_mode: :static} <- Tenant.Cache.get_site(site_key) do
      {site_key, environment_key}
    else
      _ -> nil
    end
  end

  defp submit_url do
    (Application.get_env(:brando, Brando.Forms, [])[:submit_url] || Brando.endpoint().url())
    |> String.trim_trailing("/")
  end
end
