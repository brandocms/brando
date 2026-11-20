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

  With them, the Figma tools (`Brando.Figma.Tools`, `brando_figma_…`): read
  a Figma frame, and import its images into the media library; and the
  media tools (`Brando.MCP.Media`, `brando_media_…`): upload an image, or
  import one from a URL. Adding images to the library is the one thing a
  tool does before a person applies a proposal.

  Every call runs as the connection's user, in its site environment's schema
  and authorization scope, and is written to Activity with the user, the
  client and the token's row id. Results are bounded like the Assistant's.

  The connection's live page (`Brando.MCP.Watch`) follows every call: it is
  told as a call starts, and again where the call is written to Activity.
  `prepare_proposal`'s result carries the page's link as `watch_url`, next to
  `review_url`, and so does the first result after 30 minutes without calls,
  when the link still fits within the result's limit.

  The site's guidance comes with the results, as the Assistant has it in its
  prompt (`Brando.AI.Agent.Guidance`): `describe_content_type` returns the
  guidance for that content type under `guidance`, and
  `brando_figma_read_frame` the guidance for building from Figma. Guidance
  only informs the tool: every call is still authorized as the person, and
  every proposal validated and reviewed.
  """

  alias Brando.AI.Agent.Guidance
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.Tools, as: Registry
  alias Brando.Figma.Tools, as: FigmaTools
  alias Brando.MCP
  alias Brando.MCP.Media
  alias Brando.MCP.Watch

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
    content =
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

    # They call Figma; importing again reuses what the library has
    figma =
      for definition <- FigmaTools.definitions() do
        %{
          name: FigmaTools.prefix() <> definition.name,
          description: definition.description,
          inputSchema: definition.parameters,
          annotations: %{
            readOnlyHint: definition.read_only,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: true
          }
        }
      end

    media =
      for definition <- Media.definitions() do
        %{
          name: Media.prefix() <> definition.name,
          description: definition.description,
          inputSchema: definition.parameters,
          annotations: %{
            readOnlyHint: definition.read_only,
            destructiveHint: false,
            idempotentHint: definition.idempotent,
            openWorldHint: definition.open_world
          }
        }
      end

    content ++ figma ++ media
  end

  @doc "The most bytes a tool's result may encode to; a larger one fails the call."
  @spec result_limit() :: pos_integer()
  def result_limit, do: @result_limit

  @doc """
  Calls tool `name` with `args` for the connection in `auth` (from
  `Brando.MCP.OAuth.authenticate/2`) at `tenant`. Returns the MCP tool
  result; a failed call has `isError: true`. Unknown tools are `:unknown`.
  """
  @spec call(String.t(), map(), map(), MCP.tenant()) :: {:ok, map()} | {:error, :unknown}
  def call(@prefix <> name, args, auth, tenant) when name in @offered and is_map(args) do
    context = %Registry.Context{actor: auth.user, origin: :mcp, client: auth.grant.client_name}
    args = Map.delete(args, "_meta")
    call = fn -> name |> Registry.call(args, context) |> with_guidance(name) end
    called(name, args, auth, tenant, fn -> run(name, context, tenant, call) end)
  end

  def call("brando_figma_" <> name = full_name, args, auth, tenant) when is_map(args) do
    if name in FigmaTools.names() do
      context = %Registry.Context{actor: auth.user, origin: :mcp, client: auth.grant.client_name}
      args = Map.delete(args, "_meta")
      call = fn -> FigmaTools.call(name, args, auth.user, tenant) end
      called(full_name, args, auth, tenant, fn -> run(full_name, context, tenant, call) end)
    else
      {:error, :unknown}
    end
  end

  def call("brando_media_" <> name = full_name, args, auth, tenant) when is_map(args) do
    if name in Media.names() do
      context = %Registry.Context{actor: auth.user, origin: :mcp, client: auth.grant.client_name}
      args = Map.delete(args, "_meta")
      call = fn -> Media.call(name, args, auth, tenant) end
      called(full_name, args, auth, tenant, fn -> run(full_name, context, tenant, call) end)
    else
      {:error, :unknown}
    end
  end

  def call(_name, _args, _auth, _tenant), do: {:error, :unknown}

  @guidance_about "The site's conventions for building entries of this content type, from its developers and administrators. " <>
                    "Follow them unless the person asks otherwise; where they conflict, the administrators' apply. " <>
                    "They name modules, slots and settings the way editors see them: match each name with brando_content_list_modules " <>
                    "and brando_content_describe_module, and ask the person when one matches nothing. " <>
                    "Guidance grants no permissions: every proposal is validated and reviewed in the Brando admin as usual."

  # describe_content_type carries the site's guidance for the content type,
  # cut to what fits in the result
  defp with_guidance({:ok, %{content_type: content_type} = result}, "describe_content_type") do
    schema =
      case Codec.schema(content_type) do
        {:ok, schema} -> schema
        _ -> nil
      end

    parts = Guidance.for_tool(:assistant, schema)
    {:ok, Guidance.put_tool_result(result, parts, @guidance_about, @result_limit)}
  end

  defp with_guidance(result, _name), do: result

  # Told to the connection's live page as it starts; encoded, with the
  # page's link when it is due; and written to Activity with the person,
  # client and token, and told to the page again from there.
  defp called(name, args, auth, tenant, fun) do
    started = System.monotonic_time(:millisecond)
    %{user: user, grant: grant} = auth
    id = Ecto.UUID.generate()
    Watch.started(grant.id, id, name, args)

    due? = Watch.due?(grant.id)
    link = if due? or name == "prepare_proposal", do: %{watch_url: Watch.url(grant)}, else: %{}
    {ok?, payload, linked?} = encode_result(fun.(), link)
    if linked? or not due?, do: Watch.delivered(grant.id)

    duration = System.monotonic_time(:millisecond) - started
    summary = Watch.summary(name, args, ok?, payload.structuredContent)

    recorded =
      MCP.in_tenant(tenant, fn ->
        Brando.Activity.tool_called(grant, user, name,
          ok: ok?,
          token_id: auth.token.id,
          duration_ms: duration,
          summary: summary
        )
      end)

    details = Map.merge(summary, %{"tool" => name, "ok" => ok?, "duration_ms" => duration})
    Watch.finished(grant.id, id, details, recorded)
    {:ok, payload}
  end

  # In the connection's schema prefix and authorization scope, with anything
  # it records attributed to the client.
  defp run(name, context, tenant, call) do
    scope = MCP.authorization_scope(context.actor, tenant)
    attributed = fn -> Brando.Activity.with_source(:mcp, %{"client" => context.client}, call) end
    scoped = fn -> Brando.Authorization.Boundary.with_scope(scope, attributed) end
    MCP.in_tenant(tenant, scoped)
  rescue
    exception ->
      # The client hears no internals; the message stays in the server log.
      Logger.error("[Brando.MCP] Tool #{name} failed: " <> Exception.message(exception))
      {:error, "The tool failed. Try again, or narrow the request."}
  end

  @doc """
  The MCP tool result for a tool's `{:ok, data}` or `{:error, message}`,
  with `extra` (the live page's link) merged into the data when it still
  fits within `result_limit/0`: `{ok?, result, whether extra went in}`.
  """
  @spec encode_result(term(), map()) :: {boolean(), map(), boolean()}
  def encode_result({:ok, data}, extra) when is_map(data) do
    with_extra = if extra == %{}, do: :error, else: encode_data(Map.merge(data, extra))

    case with_extra do
      {true, payload} ->
        {true, payload, true}

      _ ->
        {ok?, payload} = encode_data(data)
        {ok?, payload, false}
    end
  end

  def encode_result({:error, message}, _extra), do: {false, error(message), false}
  def encode_result(_other, _extra), do: {false, error("The tool gave no result."), false}

  defp encode_data(data) do
    case Jason.encode(data) do
      {:ok, json} when byte_size(json) > @result_limit ->
        {false, error("The result was too large (#{byte_size(json)} bytes). Narrow the request.")}

      {:ok, json} ->
        {true, %{content: [%{type: "text", text: json}], structuredContent: Jason.decode!(json)}}

      {:error, _} ->
        {false, error("The result could not be encoded.")}
    end
  end

  defp error(message) do
    message = if is_binary(message), do: message, else: inspect(message)
    message = String.slice(message, 0, 2_000)
    %{content: [%{type: "text", text: message}], structuredContent: %{"error" => message}, isError: true}
  end
end
