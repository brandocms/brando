defmodule Brando.MCP.Tools do
  @moduledoc """
  The tools the remote MCP endpoint offers: Brando's content-proposal tools
  (`Brando.Content.Proposals.Tools`), the same set and names
  (`brando_content_…`) as BrandoMCP's development stdio server, less those
  that only work inside an Assistant conversation.

  The list is fixed here rather than taken from the registry, so a tool
  added to the registry later is not offered over the network until it is
  added below. None of them approves, applies or deletes anything:
  `prepare_proposal` stores a proposal for the person to review in the admin,
  marked as coming from the connected client.

  Every call runs as the connection's user, in its site environment's schema
  and authorization scope, and is written to Activity with the user, the
  client and the token's row id. Results are bounded like the Assistant's.
  """

  alias Brando.Content.Proposals.Tools, as: Registry
  alias Brando.MCP

  require Logger

  @prefix "brando_content_"

  # Left out: `list_attachments`, `attach_folder`, `request_media` and
  # `look_at_media` work with an Assistant conversation's attachments and
  # pictures, which a connected client does not have.
  @offered ~w(list_content_types describe_content_type search_entries entry_outline list_modules describe_module
              list_entry_media list_selection_options search_assets find_media_folders prepare_proposal)

  @reads @offered -- ["prepare_proposal"]

  # As BrandoMCP and the Assistant: a result never costs a model more here.
  @result_limit 24_000

  @doc "The names of the registry's tools offered here, without the prefix."
  @spec offered() :: [String.t()]
  def offered, do: @offered

  @doc "The MCP tool definitions."
  @spec list() :: [map()]
  def list do
    for %{name: name} = definition <- Registry.definitions(), name in @offered do
      %{
        name: @prefix <> name,
        description: definition.description,
        inputSchema: definition.parameters,
        annotations: %{
          readOnlyHint: name in @reads,
          destructiveHint: false,
          idempotentHint: name in @reads,
          openWorldHint: false
        }
      }
    end
  end

  @doc """
  Calls tool `name` with `args` for the connection in `auth` (from
  `Brando.MCP.OAuth.authenticate/2`) at `tenant`. Returns the MCP tool
  result; a failed call has `isError: true`. Unknown tools are `:unknown`.
  """
  @spec call(String.t(), map(), map(), MCP.tenant()) :: {:ok, map()} | {:error, :unknown}
  def call(@prefix <> name, args, auth, tenant) when name in @offered and is_map(args) do
    started = System.monotonic_time(:millisecond)
    %{user: user, grant: grant} = auth

    context = %Registry.Context{actor: user, origin: :mcp, client: grant.client_name}
    {ok?, payload} = name |> run(Map.delete(args, "_meta"), context, tenant) |> encode()

    MCP.in_tenant(tenant, fn ->
      Brando.Activity.tool_called(grant, user, name,
        ok: ok?,
        token_id: auth.token.id,
        duration_ms: System.monotonic_time(:millisecond) - started
      )
    end)

    {:ok, payload}
  end

  def call(_name, _args, _auth, _tenant), do: {:error, :unknown}

  # In the connection's schema prefix and authorization scope, with anything
  # it records attributed to the client.
  defp run(name, args, context, tenant) do
    scope = MCP.authorization_scope(context.actor, tenant)
    call = fn -> Registry.call(name, args, context) end
    attributed = fn -> Brando.Activity.with_source(:mcp, %{"client" => context.client}, call) end
    scoped = fn -> Brando.Authorization.Boundary.with_scope(scope, attributed) end
    MCP.in_tenant(tenant, scoped)
  rescue
    exception ->
      # The client hears no internals; the message stays in the server log.
      Logger.error("[Brando.MCP] Tool #{name} failed: " <> Exception.message(exception))
      {:error, "The tool failed. Try again, or narrow the request."}
  end

  defp encode({:ok, data}) when is_map(data) do
    case Jason.encode(data) do
      {:ok, json} when byte_size(json) > @result_limit ->
        {false, error("The result was too large (#{byte_size(json)} bytes). Narrow the request.")}

      {:ok, json} ->
        {true, %{content: [%{type: "text", text: json}], structuredContent: Jason.decode!(json)}}

      {:error, _} ->
        {false, error("The result could not be encoded.")}
    end
  end

  defp encode({:error, message}), do: {false, error(message)}
  defp encode(_other), do: {false, error("The tool gave no result.")}

  defp error(message) do
    message = if is_binary(message), do: message, else: inspect(message)
    message = String.slice(message, 0, 2_000)
    %{content: [%{type: "text", text: message}], structuredContent: %{"error" => message}, isError: true}
  end
end
