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

  @doc "The guidance for `scope`, or `nil` for none."
  @callback guidance(scope()) :: String.t() | nil

  @doc """
  The guidance in effect for `conversation`, in order: the developers' from
  configuration, then the administrators' from the admin. Each part is
  `%{source: :code | :admin, text: text}`; missing parts are left out.

  A failing guidance module is logged and ignored, so the assistant keeps
  working without it.
  """
  @spec for_conversation(Brando.AI.Agent.Conversation.t()) :: [%{source: :code | :admin, text: String.t()}]
  def for_conversation(conversation) do
    code = Brando.AI.Agent.config()[:guidance] |> resolve(scope(conversation)) |> limit()
    admin = conversation.scope |> latest() |> then(&(&1 && limit(&1.text)))

    [%{source: :code, text: code}, %{source: :admin, text: admin}]
    |> Enum.reject(&is_nil(&1.text))
  end

  @doc """
  The developers' guidance for the current site and environment: the
  general text, then any text for one content type that differs from it, as
  `{content_type | nil, text}`. Shown read-only where guidance is edited.
  """
  @spec code_guidance() :: [{module() | nil, String.t()}]
  def code_guidance do
    config = Brando.AI.Agent.config()[:guidance]
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

  ## Admin guidance

  @doc "Whether `actor` may edit the guidance of the current site/environment."
  @spec configurable?(term()) :: boolean()
  def configurable?(actor) do
    if Brando.Authorization.Engine.enabled?(),
      do: Brando.Authorization.Boundary.authorize(actor, :configure, :assistant) == :ok,
      else: match?(%{role: :superuser}, actor)
  end

  @doc "The admin guidance in use in the current site/environment, or `nil`."
  @spec current() :: Version.t() | nil
  def current, do: latest(Transfer.scope())

  @doc "The latest versions of the current site/environment's admin guidance, newest first."
  @spec history(term(), keyword()) :: {:ok, [Version.t()]} | {:error, String.t()}
  def history(actor, opts \\ []) do
    Error.protect(fn ->
      authorize!(actor)

      Repo.all(
        from(v in Version,
          where: v.scope == ^Transfer.scope(),
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
  `note:` describes where the text came from, such as a copy.
  """
  @spec save(String.t(), term(), keyword()) :: {:ok, Version.t() | nil} | {:error, String.t()}
  def save(text, actor, opts \\ []) do
    Error.protect(fn ->
      authorize!(actor)
      text = text |> to_string() |> String.replace("\r\n", "\n") |> String.trim()

      if String.length(text) > @max_length,
        do: Error.fail!(dgettext("ai_agent", "Guidance can be at most %{count} characters.", count: @max_length))

      current = current()

      if (current && current.text) == text or (is_nil(current) and text == "") do
        current
      else
        {site, environment} = tenant_keys()

        %Version{
          scope: Transfer.scope(),
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
  Guidance from other sites and environments that `actor` may also
  configure, to copy from: `%{id, label, text, inserted_at}`, one per
  site/environment, newest first.
  """
  @spec sources(term()) :: [map()]
  def sources(actor) do
    if configurable?(actor) do
      scope = Transfer.scope()

      from(v in Version,
        where: v.scope != ^scope,
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

  defp latest(nil), do: nil

  defp latest(scope) do
    Repo.one(
      from(v in Version,
        where: v.scope == ^scope,
        order_by: [desc: v.inserted_at, desc: v.id],
        limit: 1,
        preload: [:author]
      )
    )
  end

  # The actor's permission in another site/environment is checked there.
  defp configurable_in?(actor, prefix) do
    if prefix == Brando.Tenant.current_prefix(),
      do: configurable?(actor),
      else: Brando.Tenant.with_prefix(prefix, fn -> configurable?(actor) end)
  rescue
    ArgumentError -> false
  end

  defp authorize!(actor) do
    unless configurable?(actor),
      do: Error.fail!(dgettext("ai_agent", "You do not have permission to change the assistant's guidance."))
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
