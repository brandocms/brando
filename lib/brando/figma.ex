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
        req_options: [],
        guidance: MyApp.FigmaGuidance

  `req_options` are merged into every API request (tests pass
  `plug: {Req.Test, Brando.Figma}`). `guidance` is the developers' baseline
  of the guidance for building from Figma that `brando_figma_read_frame`
  returns, beside the administrators' (`Brando.AI.Agent.Guidance`): a string,
  or a module implementing `Brando.AI.Agent.Guidance`.
  """

  alias Brando.MCP

  @api_url "https://api.figma.com"
  @timeout 20_000
  @err_length 200
  @replace_token "An administrator replaces it under Configuration → Integrations → Connected AI tools."

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

  @typedoc """
  What Figma says of a token (`check/1`): valid, with the handle of its
  account; expired or invalid, with Figma's `err` text;
  `:no_account_scope` when the token may not read its own account (it lacks
  `current_user:read`), so it could not be checked though it may still read
  files; or `:unreachable` when Figma could not be asked (a timeout, a
  network error, 429, a 5xx, or a 401 or 403 without Figma's error text).
  The last two say nothing of the token.
  """
  @type check ::
          {:valid, String.t() | nil}
          | {:expired, String.t() | nil}
          | {:invalid, String.t() | nil}
          | {:no_account_scope, String.t() | nil}
          | :unreachable

  @doc """
  Asks Figma about `tenant`'s token (`token/1`, the one the tools call
  with): `check/1`'s answer, or `:no_token` when there is no token the tools
  can use.
  """
  @spec check_token(MCP.tenant()) :: :no_token | check()
  def check_token(tenant) do
    case token(tenant) do
      {:ok, token} -> check(token)
      {:error, _message} -> :no_token
    end
  end

  @doc """
  Asks Figma about `token` with `GET /v1/me`, which needs the token's
  `current_user:read` scope. Only a 401 or 403 carrying Figma's error text
  is an answer about the token: expired when Figma's `err` says so;
  `:no_account_scope` when it names a missing scope, as for a token made with
  `file_content:read` alone, which still reads files; otherwise invalid.
  Anything else, a 401 or 403 without that text (a proxy or block page in
  front of Figma), a 429 and a 5xx included, is `:unreachable`.
  """
  @spec check(String.t()) :: check()
  def check(token) do
    case request(token, "/v1/me", []) do
      {:ok, body} ->
        {:valid, if(is_binary(body["handle"]), do: body["handle"])}

      {:refused, %Req.Response{status: status} = response} when status in [401, 403] ->
        verdict(figma_error(response))

      _other ->
        :unreachable
    end
  end

  # A 401 or 403 without Figma's error text came from something in front of
  # Figma (a proxy or a block page): it says nothing of the token
  defp verdict(nil), do: :unreachable

  defp verdict(err) do
    cond do
      expired?(err) -> {:expired, err}
      scope?(err) -> {:no_account_scope, err}
      true -> {:invalid, err}
    end
  end

  ## The token's expiry date

  # How many days before its expiry date the token is warned about
  @warning_days 7

  @doc "How many days before the token's expiry date the admin and the tools warn about it."
  @spec warning_days() :: pos_integer()
  def warning_days, do: @warning_days

  @doc """
  Today in the site's time zone (`Brando.timezone/0`), the day an expiry date
  is compared with.
  """
  @spec today() :: Date.t()
  def today, do: Brando.timezone() |> DateTime.now!() |> DateTime.to_date()

  @doc """
  Where the expiry date an administrator recorded for the token stands on
  `today`: `:not_recorded`; `{:later, date}`; `{:soon, date, days_left}`
  from `warning_days/0` days before it to the day itself (0 days left); or
  `{:passed, date}`. The date is what the administrator typed, so a passed
  one does not stop a call: Figma decides.
  """
  @spec expiry(Date.t() | nil, Date.t()) ::
          :not_recorded | {:later, Date.t()} | {:soon, Date.t(), non_neg_integer()} | {:passed, Date.t()}
  def expiry(expires_on, today \\ today())
  def expiry(nil, _today), do: :not_recorded

  def expiry(%Date{} = expires_on, today) do
    case Date.diff(expires_on, today) do
      days when days < 0 -> {:passed, expires_on}
      days when days <= @warning_days -> {:soon, expires_on, days}
      _days -> {:later, expires_on}
    end
  end

  @doc """
  The note a Figma tool's result carries in the token's last
  `warning_days/0` days, for the tool to pass on; nil otherwise.
  """
  @spec expiry_note(MCP.tenant()) :: String.t() | nil
  def expiry_note(tenant) do
    case expiry(MCP.figma_token_expires_on(tenant)) do
      {:soon, date, days} -> expiry_text(date, days) <> " Tell the person: " <> @replace_token
      _other -> nil
    end
  end

  @doc false
  def expiry_text(date, 0), do: "The site's Figma token expires today (#{Date.to_iso8601(date)})."
  def expiry_text(date, 1), do: "The site's Figma token expires tomorrow (#{Date.to_iso8601(date)})."
  def expiry_text(date, days), do: "The site's Figma token expires on #{Date.to_iso8601(date)}, in #{days} days."

  defp get(token, path, params) do
    case request(token, path, params) do
      {:ok, body} -> {:ok, body}
      {:refused, response} -> {:error, refusal(response)}
      :unreachable -> {:error, "Figma could not be reached. Try again in a moment."}
    end
  end

  defp request(token, path, params) do
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
      {:ok, %Req.Response{} = response} -> {:refused, response}
      {:error, _exception} -> :unreachable
    end
  end

  defp refusal(%Req.Response{status: status} = response) when status in [401, 403] do
    err = figma_error(response)

    cond do
      expired?(err) ->
        "The site's Figma token has expired. " <> @replace_token

      scope?(err) ->
        "The site's Figma token lacks the permission to read files (file_content:read)." <>
          said(err) <> " " <> @replace_token

      status == 401 or token?(err) ->
        "Figma does not accept the site's token." <> said(err) <> " " <> @replace_token

      true ->
        "Figma refused: the token's owner cannot open this file. Check that the file is shared with them." <>
          said(err)
    end
  end

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

  defp said(nil), do: ""
  defp said(err), do: " Figma said: “#{err}”."

  defp expired?(err), do: is_binary(err) and String.match?(err, ~r/expired/i)

  defp token?(err), do: is_binary(err) and String.match?(err, ~r/token/i)

  # Figma's documentation gives no body for a missing scope; its answers name
  # the scope ("Invalid scope(s): … This endpoint requires the
  # current_user:read scope")
  defp scope?(err), do: is_binary(err) and String.match?(err, ~r/scope/i)

  # Figma's `err` text (`message` in its newer endpoints' errors), as plain
  # text on one line, at most 200 characters
  defp figma_error(%Req.Response{body: body}) when is_map(body), do: plain(body["err"] || body["message"])

  defp figma_error(%Req.Response{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> plain(decoded["err"] || decoded["message"])
      _ -> nil
    end
  end

  defp figma_error(_response), do: nil

  defp plain(err) when is_binary(err) do
    if String.valid?(err) do
      err |> String.replace(~r/[\p{C}\s]+/u, " ") |> String.trim() |> String.slice(0, @err_length) |> nonblank()
    end
  end

  defp plain(_err), do: nil

  defp nonblank(""), do: nil
  defp nonblank(text), do: text
end
