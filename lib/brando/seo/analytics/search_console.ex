defmodule Brando.SEO.Analytics.SearchConsole do
  @moduledoc """
  Clicks, impressions, click-through rate and average position per page, and
  the searches a page is shown for, from the Google Search Console API.

  Authenticates as a Google Cloud service account:

    1. Create a service account and a JSON key for it in Google Cloud, and
       enable the "Google Search Console API" for the project.
    2. In Search Console, add the service account's email address as a user
       (Restricted is enough) on the property.
    3. Configure the key's JSON — or a path to the file — as `:credentials`.

  The token is signed here with `:public_key`, so no extra dependency is
  needed. Search Console reports with a delay of about two days, so the
  period ends two days ago. See `Brando.SEO.Analytics` for configuration.
  """
  alias Brando.SEO.Analytics

  @api "https://www.googleapis.com/webmasters/v3/sites/"
  @scope "https://www.googleapis.com/auth/webmasters.readonly"
  @jwt_bearer "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @lag_days 2

  @doc "Whether credentials and a property are configured."
  @spec configured?() :: boolean()
  def configured?, do: present?(config()[:credentials]) and present?(target())

  @doc "The Search Console property the figures are read from."
  @spec target() :: String.t() | nil
  def target do
    config()[:property] ||
      case Analytics.site_host() do
        nil -> nil
        host -> "sc-domain:" <> host
      end
  end

  @doc "Search figures per path over `days` days."
  @spec page_stats(pos_integer()) :: {:ok, %{String.t() => map()}} | {:error, String.t()}
  def page_stats(days) do
    with {:ok, rows} <- query(%{dimensions: ["page"], rowLimit: 25_000}, days) do
      {:ok,
       Enum.reduce(rows, %{}, fn %{"keys" => [url]} = row, acc ->
         page = figures(row) |> Map.put(:url, url)
         # http/https or www variants of one path: keep the one searched most.
         Map.update(acc, Analytics.path(url), page, &if(&1.impressions >= page.impressions, do: &1, else: page))
       end)}
    end
  end

  @doc "The searches `url` is shown for, most impressions first."
  @spec top_queries(String.t(), pos_integer(), pos_integer()) :: {:ok, [map()]} | {:error, String.t()}
  def top_queries(url, days, limit) do
    body = %{
      dimensions: ["query"],
      dimensionFilterGroups: [%{filters: [%{dimension: "page", operator: "equals", expression: url}]}],
      rowLimit: limit
    }

    with {:ok, rows} <- query(body, days) do
      {:ok,
       rows
       |> Enum.map(fn %{"keys" => [query]} = row -> Map.put(figures(row), :query, query) end)
       |> Enum.sort_by(& &1.impressions, :desc)}
    end
  end

  defp query(body, days) do
    finish = Date.add(Date.utc_today(), -@lag_days)

    body =
      Map.merge(body, %{
        startDate: Date.to_iso8601(Date.add(finish, 1 - days)),
        endDate: Date.to_iso8601(finish),
        type: "web"
      })

    with {:ok, token} <- access_token() do
      case request(
             url: @api <> URI.encode_www_form(target()) <> "/searchAnalytics/query",
             json: body,
             auth: {:bearer, token}
           ) do
        {:ok, %Req.Response{status: 200, body: body}} -> {:ok, Map.get(body, "rows", [])}
        {:ok, %Req.Response{status: status, body: body}} -> {:error, "HTTP #{status}: #{error_message(body)}"}
        {:error, exception} -> {:error, Exception.message(exception)}
      end
    end
  end

  defp figures(row) do
    %{
      clicks: round(row["clicks"] || 0),
      impressions: round(row["impressions"] || 0),
      ctr: row["ctr"] || 0.0,
      position: row["position"] || 0.0
    }
  end

  # Tokens last an hour; keep one for a little less.
  defp access_token do
    with {:ok, credentials} <- credentials() do
      key = {:seo_search_console_token, credentials["client_email"]}

      case Brando.Cache.get(key) do
        token when is_binary(token) ->
          {:ok, token}

        _ ->
          with {:ok, token, expires_in} <- request_token(credentials) do
            Brando.Cache.put(key, token, :timer.seconds(max(expires_in - 300, 60)))
            {:ok, token}
          end
      end
    end
  end

  defp request_token(credentials) do
    token_uri = credentials["token_uri"] || "https://oauth2.googleapis.com/token"

    with {:ok, assertion} <- assertion(credentials, token_uri) do
      case request(url: token_uri, form: [grant_type: @jwt_bearer, assertion: assertion]) do
        {:ok, %Req.Response{status: 200, body: %{"access_token" => token} = body}} ->
          {:ok, token, body["expires_in"] || 3600}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, "HTTP #{status} from Google sign-in: #{error_message(body)}"}

        {:error, exception} ->
          {:error, Exception.message(exception)}
      end
    end
  end

  @doc false
  # A signed RS256 JWT asserting the service account, for the token endpoint.
  def assertion(credentials, token_uri) do
    now = System.os_time(:second)
    header = %{alg: "RS256", typ: "JWT"}

    claims = %{
      iss: credentials["client_email"],
      scope: @scope,
      aud: token_uri,
      iat: now,
      exp: now + 3600
    }

    with {:ok, key} <- private_key(credentials["private_key"]) do
      signing_input = encode(header) <> "." <> encode(claims)
      signature = :public_key.sign(signing_input, :sha256, key)
      {:ok, signing_input <> "." <> Base.url_encode64(signature, padding: false)}
    end
  end

  defp encode(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp private_key(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      [] -> {:error, "The Search Console credentials hold no private key"}
    end
  rescue
    _ -> {:error, "The Search Console credentials hold no private key"}
  end

  defp private_key(_), do: {:error, "The Search Console credentials hold no private key"}

  defp credentials do
    raw = config()[:credentials]
    json = if File.regular?(raw), do: File.read!(raw), else: raw

    case Jason.decode(json) do
      {:ok, %{"client_email" => _, "private_key" => _} = credentials} -> {:ok, credentials}
      _ -> {:error, "The Search Console credentials are not a service account key"}
    end
  end

  defp request(opts) do
    [receive_timeout: 20_000, retry: false]
    |> Keyword.merge(opts)
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.post()
  end

  defp error_message(%{"error" => %{"message" => message}}), do: message
  defp error_message(%{"error_description" => message}), do: message
  defp error_message(%{"error" => error}) when is_binary(error), do: error
  defp error_message(_), do: "no details"

  defp config, do: Analytics.source_config(:search_console)

  defp present?(value), do: is_binary(value) and value != ""
end
