defmodule Brando.Tenant.InstallationHosts do
  @moduledoc """
  The hosts the installation itself uses: the endpoint's, where the admin and
  MCP answer, its static host, and its media and CDN hosts.

  They belong to no site, so no environment may be bound to one, and a client
  document on one could be a file someone uploaded.
  """

  @spec list() :: [String.t()]
  def list do
    media = [Brando.config(:media_url)] ++ Enum.map([Brando.Images, Brando.Files, Brando.Videos], &cdn_url/1)
    Enum.flat_map(endpoint_urls() ++ media, &url_host/1)
  end

  @spec member?(String.t()) :: boolean()
  def member?(host) when is_binary(host), do: normalize(host) in list()

  defp normalize(host), do: host |> String.trim() |> String.downcase() |> String.trim_trailing(".")

  # An endpoint that has not started, as in a Mix task, answers nothing
  defp endpoint_urls do
    endpoint = Brando.endpoint()
    [endpoint.url(), endpoint.static_url()]
  rescue
    _ -> []
  end

  defp url_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> [normalize(host)]
      _ -> []
    end
  end

  defp url_host(_url), do: []

  defp cdn_url(module) do
    case Brando.CDN.config(module) do
      %{enabled: true, media_url: url} -> url
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
