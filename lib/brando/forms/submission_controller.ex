defmodule Brando.Forms.SubmissionController do
  @moduledoc """
  Receives form submissions. See `Brando.Forms.Delivery` for the two routes.

  A request that accepts JSON — the script `Brando.HTML.Forms.site_form/1`
  adds — gets `%{ok: true, message: …}` or `%{ok: false, errors: …}` back.
  A plain HTML post is redirected to the page it came from, to the form's
  `#<id>-sent` or `#<id>-failed` message.

  A form with a `redirect_url` sends the visitor there once it is sent: a
  plain post is redirected to it, resolved against the page the form was on,
  and the JSON reply carries it as `redirect`.

  Both routes refuse a request whose `Origin` (or, without one, `Referer`) is
  not the site's own: the current host on a dynamic site, one of the site's
  domains on a static one.
  """
  use Phoenix.Controller, formats: [:html, :json]

  import Plug.Conn

  alias Brando.Forms
  alias Brando.Tenant

  @doc "A submission to a dynamic site, through its browser pipeline."
  def create(conn, %{"key" => key} = params) do
    if same_origin?(conn, [conn.host]),
      do: handle(conn, key, params),
      else: refuse(conn)
  end

  @doc """
  The visitor's CSRF token. The form's script asks for it before sending, so
  a form on a page served from a cache in front of the site — carrying
  whichever token the page was cached with — still sends the visitor's own.
  """
  def csrf_token(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store, private")
    |> json(%{token: Plug.CSRFProtection.get_csrf_token()})
  end

  @doc "A submission from a statically delivered site, without a session."
  def create_static(conn, %{"site" => site_key, "environment" => environment_key, "key" => key} = params) do
    with %{delivery_mode: :static} = site <- Tenant.Cache.get_site(site_key),
         %{} = environment <- Tenant.Cache.get_env(site_key, environment_key),
         true <- static_origin?(conn, site, environment) do
      Tenant.put_prefix(Tenant.prefix(site, environment))

      conn
      |> allow_origin()
      |> handle(key, params)
    else
      _ -> refuse(conn)
    end
  end

  defp handle(conn, key, params) do
    meta = %{
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first(),
      url: referer(conn)
    }

    case Forms.submit(key, params, meta) do
      {:ok, _submission, form} ->
        sent(conn, form)

      {:error, {:invalid, errors}, form} ->
        respond(conn, form, 422, %{ok: false, errors: errors}, "failed")

      {:error, :rate_limited, form} ->
        message = Forms.message(:rate_limited, form.language)
        respond(conn, form, 429, %{ok: false, message: message}, "failed")

      {:error, :rejected, form} ->
        message = Forms.message(:spam_check, form.language)
        respond(conn, form, 403, %{ok: false, message: message}, "failed")

      {:error, :not_found} ->
        conn |> put_status(404) |> respond_plain(%{ok: false})

      {:error, _changeset} ->
        conn |> put_status(500) |> respond_plain(%{ok: false})
    end
  end

  defp sent(conn, %{redirect_url: url} = form) when is_binary(url) and url != "" do
    if json?(conn),
      do: json(conn, %{ok: true, message: Forms.success_message(form), redirect: url}),
      else: conn |> put_status(303) |> redirect(external: resolve(conn, url))
  end

  defp sent(conn, form), do: respond(conn, form, 200, %{ok: true, message: Forms.success_message(form)}, "sent")

  defp respond(conn, form, status, body, outcome) do
    if json?(conn) do
      conn |> put_status(status) |> json(body)
    else
      conn
      |> put_status(303)
      |> redirect(external: back_url(conn, "#{dom_id(conn, form)}-#{outcome}"))
    end
  end

  # The form's element id, which its messages are named after.
  defp dom_id(%{params: %{"_form_id" => id}}, _form) when is_binary(id) do
    if Regex.match?(~r/^[A-Za-z][\w-]{0,100}$/, id), do: id, else: "form"
  end

  defp dom_id(_conn, form), do: "form-#{form.key}"

  defp respond_plain(conn, body) do
    if json?(conn), do: json(conn, body), else: send_resp(conn, conn.status, "")
  end

  defp refuse(conn), do: conn |> put_status(403) |> respond_plain(%{ok: false})

  defp json?(conn) do
    conn |> get_req_header("accept") |> Enum.any?(&String.contains?(&1, "application/json"))
  end

  # The page the form was on, so a plain post lands back on its message.
  defp back_url(conn, anchor) do
    case referer(conn) do
      nil -> "/##{anchor}"
      url -> (url |> String.split("#") |> hd()) <> "##{anchor}"
    end
  end

  # A path is on the site the form was on, which for a static site is not
  # the host that received the post.
  defp resolve(conn, "/" <> _ = path) do
    case referer(conn) do
      nil -> path
      url -> url |> URI.merge(path) |> URI.to_string()
    end
  end

  defp resolve(_conn, url), do: url

  defp referer(conn), do: conn |> get_req_header("referer") |> List.first()

  defp origin_host(conn) do
    case conn |> get_req_header("origin") |> List.first() || referer(conn) do
      nil -> nil
      "null" -> :opaque
      url -> URI.parse(url).host
    end
  end

  # A browser always sends one of the two on a cross-site post; a request with
  # neither is not one a third-party page could have made a visitor send.
  defp same_origin?(conn, hosts) do
    case origin_host(conn) do
      nil -> true
      :opaque -> false
      host -> host in hosts
    end
  end

  defp static_origin?(conn, site, environment) do
    with host when is_binary(host) <- origin_host(conn),
         {%{id: site_id}, %{id: environment_id}} <- Tenant.Cache.get_env_by_domain(host) do
      site_id == site.id and environment_id == environment.id
    else
      _ -> false
    end
  end

  # The static site's enhancement script reads the JSON reply cross-origin.
  defp allow_origin(conn) do
    case get_req_header(conn, "origin") do
      [origin | _] -> conn |> put_resp_header("access-control-allow-origin", origin) |> put_resp_header("vary", "origin")
      _ -> conn
    end
  end
end
