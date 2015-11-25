defmodule Brando.Instagram.AuthToken do
  @moduledoc """
  Fetches our user's auth_token from Instagram.

  Since the API changes in November 2015, Instagram's API now requires you to
  supply each API call with an `auth_token`.
  """

  @token_filename "token.json"
  @http_lib Brando.Instagram.config(:token_http_lib)

  import Brando.Instagram, only: [config: 1]

  @doc """
  Retrieves token from Instagram.

  * Gets the csrf token from the login page
  * Posts our credentials to authorize
  * Extracts the token from Instagram's callback
  * Stores token in a file under our otp_app's priv dir
  * Returns the token

  """
  def retrieve_token do
    get_login_page
    |> post_login
    |> post_authorize
    |> post_callback
    |> extract_token
    |> store_token
    |> return_token
  end

  @doc """
  Loads token from file

  If file isn't found, retrieve a new token.
  """
  def load_token do
    case File.read(token_file()) do
      {:ok, contents} -> Poison.decode!(contents)
      {:error, :enoent} -> retrieve_token()
    end
  end

  defp get_login_page do
    url = host() <> action()
    @http_lib.get!(url, default_headers())
  end

  defp post_login(response) do
    cookies = get_cookies(response.headers)
    csrf_token = cookies["csrftoken"]
    mid_token = cookies["mid"]
    url = host() <> action()

    headers = default_headers() ++ [
      {"cookie", "mid=#{mid_token}; csrftoken=#{csrf_token}"},
      {"referer", url},
    ]

    body = {:form, [
      csrfmiddlewaretoken: csrf_token,
      username: config(:username),
      password: config(:password),
    ]}

    @http_lib.post!(url, body, headers)
  end

  defp post_authorize(response) do
    cookies = get_cookies(response.headers)
    csrf_token = cookies["csrftoken"]
    mid_token = cookies["mid"]
    url = host() <> action

    headers = default_headers() ++ [
      {"cookie", "mid=#{mid_token}; csrftoken=#{csrf_token}"},
      {"referer", url},
    ]

    body = {:form, [
      csrfmiddlewaretoken: csrf_token,
      username: config(:username),
      password: config(:password),
    ]}

    @http_lib.post!(url, body, headers)
  end

  defp post_callback(response) do
    location = response.headers["Location"]
    cookies = get_cookies(response.headers)
    csrf_token = cookies["csrftoken"]
    mid_token = cookies["mid"]
    session_token = cookies["sessionid"]
    referer = host() <> action()

    headers = [
      {"cookie", "mid=#{mid_token}; csrftoken=#{csrf_token}; sessionid=#{session_token}"},
      {"referer", referer},
    ]

    body = {:form, [
      csrfmiddlewaretoken: csrf_token,
      username: config(:username),
      password: config(:password),
      allow: "Authorize"
    ]}

    @http_lib.post!(location, body, headers)
  end

  defp extract_token(response) do
    response
    |> Map.get(:headers)
    |> Enum.into(%{})
    |> Map.get("Location")
    |> URI.parse
    |> Map.get(:fragment)
    |> URI.decode_query
  end

  defp store_token(token) do
    File.mkdir_p!(token_path())
    File.write!(token_file(), Poison.encode!(token))
    token
  end

  defp return_token(%{"auth_token" => auth_token}), do: auth_token

  defp token_path, do:
    Application.app_dir(Brando.config(:otp_app), config(:token_path))

  defp token_file, do:
    Path.join([token_path(), @token_filename])

  defp parse_cookie({"Set-Cookie", content}) do
    content
    |> :hackney_cookie.parse_cookie
    |> List.first
  end

  defp parse_cookie({_, _}) do
    nil
  end

  defp get_cookies(headers), do:
    Enum.filter_map(headers, &(parse_cookie/1), &(parse_cookie/1))

  defp host, do: "https://www.instagram.com"

  defp action do
    "/accounts/login/?force_classic_login=" <>
    "&next=/oauth/authorize/%3Fclient_id%3D#{config(:client_id)}" <>
    "%26redirect_uri%3Dhttp%3A//localhost%26response_type%3Dtoken"
  end

  defp default_headers() do
    [
      {"accept", "text/html,application/xml;q=0.9,image/webp,*/*;q=0.8"},
      {"accept-encoding", "gzip, deflate"},
      {"accept-language", "en-US,en;q=0.8,nb;q=0.6,sv;q=0.4"},
      {"cache-control", "no-cache"},
      {"content-type", "application/x-www-form-urlencoded"},
      {"origin", host()},
      {"pragma", "no-cache"},
      {"upgrade-insecure-requests", "1"},
      {"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) " <>
       "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.86 Safari/537.36"},
    ]
  end
end