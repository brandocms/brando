defmodule Brando.Figma do
  @moduledoc """
  Reads a frame of a Figma file through Figma's REST API, for connected AI
  tools to rebuild a design as content: its sections, texts and images
  (`Brando.Figma.Frame`), and its images imported into the media library
  (`Brando.Figma.Import`). The MCP endpoint offers both as tools
  (`Brando.Figma.Tools`); see the guide, `guides/mcp.md`.

  Figma is called with the site environment's access token, which an
  administrator adds under Configuration → Integrations → Connected AI tools
  (`Brando.MCP.put_figma_token/3`). Without one the tools say so.

  ## Configuration

      config :brando, Brando.Figma,
        api_url: "https://api.figma.com",
        req_options: []

  `req_options` are merged into every API request (tests pass
  `plug: {Req.Test, Brando.Figma}`).
  """

  alias Brando.MCP

  @api_url "https://api.figma.com"
  @timeout 20_000

  @type link :: %{file_key: String.t(), node_id: String.t()}

  defp config, do: Brando.config(__MODULE__) || []

  @doc """
  The file and node of a Figma link, such as
  `https://www.figma.com/design/35BOzF…/Name?node-id=2950-4703`. The link
  must name a node (`node-id`), as a link copied from a selected frame does.
  A branch link names the branch's file.
  """
  @spec parse_url(term()) :: {:ok, link()} | {:error, String.t()}
  def parse_url(url) when is_binary(url) do
    with {:ok, %URI{host: host, path: path, query: query}} <- uri(url),
         true <- figma_host?(host) || {:error, "That is not a Figma link (figma.com)."},
         {:ok, file_key} <- file_key(String.split(path || "", "/", trim: true)),
         {:ok, node_id} <- node_id(URI.decode_query(query || "")) do
      {:ok, %{file_key: file_key, node_id: node_id}}
    end
  end

  def parse_url(_url), do: {:error, "Give the Figma link as a string."}

  defp uri(url) do
    case URI.new(String.trim(url)) do
      {:ok, uri} -> {:ok, uri}
      {:error, _part} -> {:error, "That is not a link."}
    end
  end

  defp figma_host?(host) when is_binary(host), do: String.downcase(host) in ["figma.com", "www.figma.com"]
  defp figma_host?(_host), do: false

  defp file_key([kind, _key, "branch", branch_key | _]) when kind in ~w(design file proto board),
    do: checked_key(branch_key)

  defp file_key([kind, key | _]) when kind in ~w(design file proto board), do: checked_key(key)
  defp file_key(_segments), do: {:error, "The link does not name a Figma file."}

  defp checked_key(key) do
    if String.match?(key, ~r/\A[A-Za-z0-9]{10,64}\z/),
      do: {:ok, key},
      else: {:error, "The link does not name a Figma file."}
  end

  # Links write a node id as "2950-4703", the API as "2950:4703"; an
  # instance's sublayer has ";"-separated parts.
  defp node_id(%{"node-id" => node_id}) do
    node_id = String.replace(node_id, "-", ":")

    if String.match?(node_id, ~r/\A(I?\d+:\d+)(;\d+:\d+)*\z/),
      do: {:ok, node_id},
      else: {:error, "The link's node-id is not one Figma uses."}
  end

  defp node_id(_query),
    do: {:error, "The link names no frame. In Figma, select the frame and copy its link (it has ?node-id=…)."}

  @doc """
  The token of `tenant`, or the error a tool shows when there is none.
  """
  @spec token(MCP.tenant()) :: {:ok, String.t()} | {:error, String.t()}
  def token(tenant) do
    case MCP.figma_token(tenant) do
      {:ok, token} ->
        {:ok, token}

      :error ->
        {:error,
         "Figma is not connected to this site. An administrator adds a Figma access token under " <>
           "Configuration → Integrations → Connected AI tools."}
    end
  end

  @doc """
  The node `link` names, with the file's name and the components and
  component sets its instances use: `%{file_name, document, components,
  component_sets}`.
  """
  @spec node(String.t(), link()) :: {:ok, map()} | {:error, String.t()}
  def node(token, %{file_key: file_key, node_id: node_id}) do
    case get(token, "/v1/files/#{file_key}/nodes", ids: node_id) do
      {:ok, %{"nodes" => %{^node_id => %{"document" => document} = node}} = body} ->
        {:ok,
         %{
           file_name: body["name"],
           document: document,
           components: node["components"] || %{},
           component_sets: node["componentSets"] || %{}
         }}

      {:ok, _body} ->
        {:error, "Figma has no node #{node_id} in that file. Copy the frame's link again."}

      {:error, _message} = error ->
        error
    end
  end

  @doc """
  Download URLs of the file's image fills, by image ref: the originals as
  placed, not renders. Figma's URLs expire after a while; use them at once.
  """
  @spec image_urls(String.t(), String.t()) :: {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def image_urls(token, file_key) do
    case get(token, "/v1/files/#{file_key}/images", []) do
      {:ok, %{"meta" => %{"images" => images}}} when is_map(images) -> {:ok, images}
      {:ok, _body} -> {:error, "Figma did not list the file's images."}
      {:error, _message} = error -> error
    end
  end

  defp get(token, path, params) do
    options =
      Keyword.merge(
        [
          base_url: Keyword.get(config(), :api_url, @api_url),
          url: path,
          params: params,
          headers: [{"x-figma-token", token}],
          receive_timeout: @timeout,
          connect_options: [timeout: @timeout],
          retry: false,
          redirect: false
        ],
        Keyword.get(config(), :req_options, [])
      )

    case Req.get(options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{} = response} -> {:error, refusal(response)}
      {:error, _exception} -> {:error, "Figma could not be reached. Try again in a moment."}
    end
  end

  defp refusal(%Req.Response{status: status}) when status in [401, 403],
    do:
      "Figma refused the site's token, or its owner cannot open this file. " <>
        "Check that the file is shared with them, or ask an administrator to replace the token."

  defp refusal(%Req.Response{status: 404}), do: "Figma has no such file, or the token's owner cannot open it."

  defp refusal(%Req.Response{status: 429} = response) do
    wait =
      case Req.Response.get_header(response, "retry-after") do
        [seconds | _] -> " in #{seconds} seconds"
        _ -> " later"
      end

    "Figma's limit on API calls for the token's owner is reached. Try again#{wait}."
  end

  defp refusal(%Req.Response{status: status}), do: "Figma answered #{status}. Try again in a moment."
end
