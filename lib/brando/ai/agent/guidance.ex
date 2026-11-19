defmodule Brando.AI.Agent.Guidance do
  @moduledoc """
  Site guidance for the content assistant: the site's own conventions for
  building content from its modules.

  Guidance comes from two places. Administrators edit it per site and
  environment under Configuration → Assistant guidance; every save is a
  `Brando.AI.Agent.Guidance.Version`. Developers can ship a baseline in the
  configuration, described below. The prompt includes both, and the
  administrators' applies where they conflict.

      config :brando, Brando.AI.Agent,
        guidance: MyApp.AssistantGuidance

  The value is a string, or a module implementing this behaviour. The module
  is called when a run builds its prompt, in the conversation's site and
  environment, so one application can give each site its own conventions:

      defmodule MyApp.AssistantGuidance do
        @behaviour Brando.AI.Agent.Guidance

        @impl true
        def guidance(%{content_type: MyApp.Articles.Article}) do
          \"\"\"
          - Start an article with the "Article lede" module for its introduction.
          - A long introduction goes partly in "Article lede" and continues in "Article text".
          - Portrait image pairs use "Two images" with the narrow setting on.
          \"\"\"
        end

        def guidance(_scope), do: nil
      end

  Name modules, slots and settings the way editors see them. The assistant
  matches them against the modules the block field allows; a module, slot or
  setting that does not exist there makes it ask instead of guess, and every
  proposal is still validated and reviewed as usual. Guidance cannot grant
  permissions or skip the review.

  Guidance is limited to 12,000 characters; longer text is cut and logged.

  ## Connected AI tools

  Tools connected over MCP (`Brando.MCP`) get the same guidance through the
  tools' results, since some clients ignore a server's instructions:
  `brando_content_describe_content_type` returns the guidance for that
  content type (`for_tool/2`), both parts together within the same 12,000
  characters.

  The guidance for building from Figma is a second kind, edited next to the
  Figma token under Configuration → Integrations → Connected AI tools and
  versioned the same way, with its own baseline in the configuration:

      config :brando, Brando.Figma,
        guidance: MyApp.FigmaGuidance

  A string, or a module implementing this behaviour, called with
  `content_type: nil`. `brando_figma_read_frame` returns it with a frame. The
  content assistant's prompt never includes it.
  """
  use Gettext, backend: Brando.Gettext
  import Ecto.Query, only: [from: 2]
  require Logger

  alias Brando.AI.Agent.Guidance.Version
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.Error
  alias Brando.Repo

  @max_length 12_000

  @typedoc """
  Where the conversation runs: the site and environment keys (both `nil`
  without tenancy) and the content type of the entry it was opened for, if
  any.
  """
  @type scope :: %{site: String.t() | nil, environment: String.t() | nil, content_type: module() | nil}

  @typedoc "Which guidance: the content assistant's, or the one for building from Figma."
  @type kind :: :assistant | :figma

  @type part :: %{source: :code | :admin, text: String.t()}

  @doc "The guidance for `scope`, or `nil` for none."
  @callback guidance(scope()) :: String.t() | nil

  @doc """
  The guidance in effect for `conversation`, in order: the developers' from
  configuration, then the administrators' from the admin. Each part is
  `%{source: :code | :admin, text: text}`; missing parts are left out.

  A failing guidance module is logged and ignored, so the assistant keeps
  working without it.
  """
  @spec for_conversation(Brando.AI.Agent.Conversation.t()) :: [part()]
  def for_conversation(conversation) do
    code = Brando.AI.Agent.config()[:guidance] |> resolve(scope(conversation)) |> limit()
    admin = conversation.scope |> latest(:assistant) |> then(&(&1 && limit(&1.text)))

    [%{source: :code, text: code}, %{source: :admin, text: admin}]
    |> Enum.reject(&is_nil(&1.text))
  end

  @doc """
  The guidance a connected AI tool gets in the current site/environment, in
  the same order and shape as `for_conversation/1`: the `:assistant` kind
  for `content_type`, or the `:figma` kind. Both parts together are at most
  12,000 characters; the developers' part is cut first, since the
  administrators' applies where they conflict.
  """
  @spec for_tool(kind(), module() | nil) :: [part()]
  def for_tool(kind, content_type \\ nil) do
    {site, environment} = tenant_keys()
    scope = %{site: site, environment: environment, content_type: if(kind == :assistant, do: content_type)}
    code = kind |> code_config() |> resolve(scope) |> limit()
    admin = Transfer.scope() |> latest(kind) |> then(&(&1 && limit(&1.text)))

    [%{source: :code, text: code}, %{source: :admin, text: admin}]
    |> Enum.reject(&is_nil(&1.text))
    |> fit(@max_length, :characters)
  end

  @doc """
  Cuts `parts` to at most `max` characters, or bytes as JSON string
  contents (`:json`: a quote, backslash or newline takes two, a control
  character six), together: the developers' part first, then the
  administrators'. A part cut to nothing is left out; a cut is logged.
  """
  @spec fit([part()], integer(), :characters | :json) :: [part()]
  def fit(parts, max, unit) do
    admin = Enum.find(parts, &(&1.source == :admin))
    code = Enum.find(parts, &(&1.source == :code))
    admin_text = admin && cut(admin.text, max, unit)
    room = max - size(admin_text || "", unit)
    code_text = code && cut(code.text, room, unit)

    [%{source: :code, text: code_text}, %{source: :admin, text: admin_text}]
    |> Enum.reject(&(&1.text in [nil, ""]))
  end

  defp size(text, :characters), do: String.length(text)
  defp size(text, :json), do: byte_size(Jason.encode!(text)) - 2

  defp cut(text, max, unit) do
    cond do
      size(text, unit) <= max ->
        text

      max <= 0 ->
        Logger.warning("Guidance for connected tools is over its limit; a part was left out.")
        nil

      true ->
        Logger.warning("Guidance for connected tools is over its limit and was cut.")
        take(text, max, unit)
    end
  end

  defp take(text, max, :characters), do: String.slice(text, 0, max)

  # JSON escapes each code point on its own, so the graphemes' encoded
  # sizes add up to the text's
  defp take(text, max, :json) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {taken, bytes} ->
      bytes = bytes + size(grapheme, :json)
      if bytes > max, do: {:halt, {taken, bytes}}, else: {:cont, {[grapheme | taken], bytes}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end

  @doc """
  `result` with `parts` under `:guidance`, as a tool result gives them:
  what they are and how to use them (`about`), then the developers' and the
  administrators' text. The guidance is cut, the developers' part first, so
  that `result` encodes to at most `limit` bytes of JSON (`:infinity` for
  no cut), and left out when none fits or there is none: a tool never fails
  for its guidance.
  """
  @spec put_tool_result(map(), [part()], String.t(), pos_integer() | :infinity) :: map()
  def put_tool_result(result, [], _about, _limit), do: result

  def put_tool_result(result, parts, about, :infinity), do: Map.put(result, :guidance, tool_result(parts, about))

  def put_tool_result(result, parts, about, limit) do
    guided = Map.put(result, :guidance, tool_result(parts, about))
    over = byte_size(Jason.encode!(guided)) - limit

    if over <= 0 do
      guided
    else
      # Each pass cuts at least `over` bytes, so it ends with a fit or no parts
      text = parts |> Enum.map(&size(&1.text, :json)) |> Enum.sum()
      put_tool_result(result, fit(parts, text - over, :json), about, limit)
    end
  end

  defp tool_result(parts, about) do
    Enum.reduce(parts, %{about: about}, fn
      %{source: :code, text: text}, result -> Map.put(result, :developers, text)
      %{source: :admin, text: text}, result -> Map.put(result, :administrators, text)
    end)
  end

  defp code_config(:assistant), do: Brando.AI.Agent.config()[:guidance]
  defp code_config(:figma), do: (Brando.config(Brando.Figma) || [])[:guidance]

  @doc """
  The developers' guidance for the current site and environment: the
  general text, then any text for one content type that differs from it, as
  `{content_type | nil, text}`. Shown read-only where guidance is edited.
  """
  @spec code_guidance() :: [{module() | nil, String.t()}]
  def code_guidance do
    config = code_config(:assistant)
    {site, environment} = tenant_keys()

    at = fn content_type ->
      config |> resolve(%{site: site, environment: environment, content_type: content_type}) |> limit()
    end

    general = at.(nil)

    specific =
      for schema <- Brando.Content.Transfer.Catalog.schemas(),
          text = at.(schema),
          text != general,
          do: {schema, text}

    if(general, do: [{nil, general}], else: []) ++ specific
  end

  @doc "The developers' guidance for building from Figma in the current site and environment, or `nil`."
  @spec code_figma_guidance() :: String.t() | nil
  def code_figma_guidance do
    {site, environment} = tenant_keys()
    :figma |> code_config() |> resolve(%{site: site, environment: environment, content_type: nil}) |> limit()
  end

  ## Admin guidance

  @doc """
  Whether `actor` may edit the guidance of the current site/environment, of
  either kind. The Figma guidance shapes what connected tools propose as
  much as the assistant's shapes the assistant, so it takes the same right.
  """
  @spec configurable?(term()) :: boolean()
  def configurable?(actor) do
    if Brando.Authorization.Engine.enabled?(),
      do: Brando.Authorization.Boundary.authorize(actor, :configure, :assistant) == :ok,
      else: match?(%{role: :superuser}, Brando.Authorization.Boundary.fresh_role(actor))
  end

  @doc "The admin guidance of `kind` in use in the current site/environment, or `nil`."
  @spec current(kind()) :: Version.t() | nil
  def current(kind \\ :assistant), do: latest(Transfer.scope(), kind)

  @doc """
  The latest versions of the current site/environment's admin guidance,
  newest first. `kind:` (`:assistant` by default) and `limit:` (20).
  """
  @spec history(term(), keyword()) :: {:ok, [Version.t()]} | {:error, String.t()}
  def history(actor, opts \\ []) do
    kind = Keyword.get(opts, :kind, :assistant)

    Error.protect(fn ->
      authorize!(actor, kind)

      Repo.all(
        from(v in Version,
          where: v.scope == ^Transfer.scope() and v.kind == ^kind,
          order_by: [desc: v.inserted_at, desc: v.id],
          limit: ^Keyword.get(opts, :limit, 20),
          preload: [:author]
        )
      )
    end)
  end

  @doc """
  Save `text` as the admin guidance of the current site/environment. An
  empty text clears it. Saving the text already in use adds no version.
  `note:` describes where the text came from, such as a copy; `kind:` which
  guidance it is (`:assistant` by default).
  """
  @spec save(String.t(), term(), keyword()) :: {:ok, Version.t() | nil} | {:error, String.t()}
  def save(text, actor, opts \\ []) do
    kind = Keyword.get(opts, :kind, :assistant)

    Error.protect(fn ->
      authorize!(actor, kind)
      text = text |> to_string() |> String.replace("\r\n", "\n") |> String.trim()

      if String.length(text) > @max_length,
        do: Error.fail!(dgettext("ai_agent", "Guidance can be at most %{count} characters.", count: @max_length))

      current = current(kind)

      if (current && current.text) == text or (is_nil(current) and text == "") do
        current
      else
        {site, environment} = tenant_keys()

        %Version{
          scope: Transfer.scope(),
          kind: kind,
          prefix: Brando.Tenant.current_prefix(),
          site_key: site,
          environment_key: environment,
          text: text,
          note: opts[:note],
          author_id: actor.id
        }
        |> Repo.insert!()
        |> Repo.preload(:author)
      end
    end)
  end

  @doc """
  Assistant guidance from other sites and environments that `actor` may
  also configure, to copy from: `%{id, label, text, inserted_at}`, one per
  site/environment, newest first.
  """
  @spec sources(term()) :: [map()]
  def sources(actor) do
    if configurable?(actor) do
      scope = Transfer.scope()

      from(v in Version,
        where: v.scope != ^scope and v.kind == :assistant,
        distinct: v.scope,
        order_by: [asc: v.scope, desc: v.inserted_at, desc: v.id]
      )
      |> Repo.all()
      |> Enum.filter(&(&1.text != "" and configurable_in?(actor, &1.prefix)))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.map(
        &%{id: &1.id, label: label(&1.site_key, &1.environment_key), text: &1.text, inserted_at: &1.inserted_at}
      )
    else
      []
    end
  end

  @doc "A source from `sources/1`, by id."
  @spec source(Ecto.UUID.t(), term()) :: {:ok, map()} | {:error, String.t()}
  def source(id, actor) do
    case Enum.find(sources(actor), &(&1.id == id)) do
      nil -> {:error, dgettext("ai_agent", "This guidance is not available.")}
      source -> {:ok, source}
    end
  end

  @doc "A label for the current site/environment, or another one's keys."
  @spec label(String.t() | nil, String.t() | nil) :: String.t()
  def label(site_key \\ elem(tenant_keys(), 0), environment_key \\ elem(tenant_keys(), 1))

  def label(nil, _environment_key), do: Brando.config(:app_name) || dgettext("ai_agent", "This site")

  def label(site_key, environment_key) do
    site = Brando.Tenant.Registry.get_site_by_key(site_key)
    environments = (site && Map.get(site, :environments)) || []

    environment =
      case Enum.find(List.wrap(environments), &(&1.key == environment_key)) do
        nil -> environment_key
        found -> found.name || found.key
      end

    Enum.join([(site && site.name) || site_key, environment], " / ")
  end

  defp latest(nil, _kind), do: nil

  defp latest(scope, kind) do
    Repo.one(
      from(v in Version,
        where: v.scope == ^scope and v.kind == ^kind,
        order_by: [desc: v.inserted_at, desc: v.id],
        limit: 1,
        preload: [:author]
      )
    )
  end

  # The actor's permission in another site/environment is checked there, in
  # that site's scope: an admin screen has pinned the one it is open in.
  defp configurable_in?(actor, prefix) do
    Brando.Tenant.with_prefix(prefix, fn ->
      scope = Brando.Authorization.Scope.current(actor)
      Brando.Authorization.Boundary.with_scope(scope, fn -> configurable?(actor) end)
    end)
  rescue
    ArgumentError -> false
  end

  defp authorize!(actor, kind) do
    unless configurable?(actor) do
      case kind do
        :assistant -> Error.fail!(dgettext("ai_agent", "You do not have permission to change the assistant's guidance."))
        :figma -> Error.fail!(dgettext("ai_agent", "You do not have permission to change the guidance for Figma."))
      end
    end
  end

  @doc "The scope the guidance module receives for `conversation`."
  @spec scope(Brando.AI.Agent.Conversation.t()) :: scope()
  def scope(conversation) do
    {site, environment} = tenant_keys()

    content_type =
      with %{"content_type" => name} <- conversation.target,
           {:ok, schema} <- Brando.Content.Proposals.Codec.schema(name) do
        schema
      else
        _ -> nil
      end

    %{site: site, environment: environment, content_type: content_type}
  end

  defp tenant_keys do
    with "tenant_" <> rest <- Brando.Tenant.current_prefix(),
         [site, environment] <- String.split(rest, "_", parts: 2) do
      {site, environment}
    else
      _ -> {nil, nil}
    end
  end

  defp resolve(nil, _scope), do: nil
  defp resolve(text, _scope) when is_binary(text), do: text

  defp resolve(module, scope) when is_atom(module) do
    case module.guidance(scope) do
      text when is_binary(text) or is_nil(text) ->
        text

      other ->
        Logger.error("#{inspect(module)}.guidance/1 returned #{inspect(other)}; expected a string or nil.")
        nil
    end
  rescue
    error ->
      Logger.error("Content assistant guidance failed: " <> Exception.format(:error, error, __STACKTRACE__))
      nil
  end

  defp limit(nil), do: nil

  defp limit(text) do
    case String.trim(text) do
      "" ->
        nil

      text ->
        if String.length(text) > @max_length do
          Logger.warning("Content assistant guidance is longer than #{@max_length} characters and was cut.")
          String.slice(text, 0, @max_length)
        else
          text
        end
    end
  end
end
