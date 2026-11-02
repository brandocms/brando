defmodule Brando.Videos.ProviderLibrary do
  @moduledoc """
  Browse a video provider's own library and add an existing video to Brando's.

  Every configured provider whose uploader implements the optional library
  callbacks of `Brando.Videos.Uploader` — `list_remote/1`, `import_remote/3`
  and `library_meta_path/0` — can be browsed, whether or not the video was ever
  uploaded through Brando.

  ## Imported videos are never deleted remotely

  A video added this way gets `meta["imported"] = true`. Deleting it in Brando
  removes the record only; `delete_remote_on` does not apply to it, because
  the video belongs to whoever put it in the provider's library and may be in
  use elsewhere. See `Brando.Videos.Uploader.get_delete_timing/1`.

  ## Sharing between sites

  Provider credentials are the installation's. With `tenancy_mode: :multi`,
  a site browses the provider libraries only when it is in a provider
  library group (`Brando.Sites.Site`'s `provider_library_group`, which an
  installation superuser sets on the Sites screen). A site in no group, the
  default, gets no "Add from …" button: `providers/0` is empty and `import/4`
  refuses.

  A site in a group lists, and may add, the videos the sites of its group
  hold (`Brando.Videos.ProviderHoldings`) and those no site holds, such as
  videos uploaded in the provider's own dashboard. A video only sites
  outside the group hold is left out of the listing and refused on adding,
  and so is every video when it cannot be told which sites hold them.

  Without tenancy, or with one site, the whole account is listed.

  ## One record per remote video

  Adding a video that already has a record — uploaded through Brando, or added
  before — returns that record instead of creating another. Two records for one
  remote video would mean deleting either could remove the video from under
  the other, and the provider webhooks look a video up by its remote id and
  expect one answer.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Videos.ProviderHoldings
  alias Brando.Videos.Uploaders
  alias Brando.Videos.Video

  require Logger

  @typedoc "One remote video, the same shape for every provider."
  @type item :: %{
          remote_id: String.t(),
          title: String.t() | nil,
          thumbnail_url: String.t() | nil,
          duration: number() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          status: :ready | :processing | :errored,
          created_at: String.t() | nil,
          playable?: boolean(),
          video_id: pos_integer() | nil
        }

  @type page :: %{items: [item()], next: term() | nil}

  @providers [
    {:mux, Uploaders.Mux, "Mux"},
    {:bunny, Uploaders.Bunny, "Bunny Stream"},
    {:cloudflare, Uploaders.Cloudflare, "Cloudflare Stream"},
    {:vimeo, Uploaders.Vimeo, "Vimeo"}
  ]

  # A filtered page can come back empty while the provider has more. Up to
  # this many provider pages are read to find something to show.
  @max_filtered_pages 5

  @doc """
  The providers that can be browsed right now, from the current site:
  configured, and implementing the library callbacks. Each is
  `%{strategy:, label:, search?:}`. Empty for a site in no provider library
  group of a multi-site installation.
  """
  @spec providers() :: [%{strategy: atom(), label: String.t(), search?: boolean()}]
  def providers do
    providers(scope())
  end

  defp providers(:isolated), do: []
  defp providers(_scope), do: configured_providers()

  defp configured_providers do
    for {strategy, module, label} <- @providers,
        Code.ensure_loaded?(module),
        function_exported?(module, :list_remote, 1),
        module.configured?() do
      %{strategy: strategy, label: label, search?: searchable?(module)}
    end
  end

  @doc """
  Lists one page of `strategy`'s library, newest first.

  ## Options

    * `:cursor` — the `next` value of the previous page
    * `:query` — a search string, for providers whose API searches
    * `:per_page` — defaults to 24

  Each item's `:video_id` is the id of the Brando record that already holds it,
  or `nil`. For a site in a provider library group, the videos only other
  sites hold are left out (see "Sharing between sites").
  """
  @spec list(atom(), keyword()) :: {:ok, page()} | {:error, term()}
  def list(strategy, opts \\ []) do
    opts = Keyword.put_new(opts, :per_page, 24)
    scope = scope()

    with {:ok, module} <- provider(strategy, scope),
         {:ok, %{items: items} = page} <- list_page(module, scope, opts, @max_filtered_pages) do
      existing = existing_video_ids(module.library_meta_path(), Enum.map(items, & &1.remote_id))
      {:ok, %{page | items: Enum.map(items, &Map.put(&1, :video_id, existing[&1.remote_id]))}}
    end
  end

  defp list_page(module, :account, opts, _pages_left), do: guarded(fn -> module.list_remote(opts) end)

  defp list_page(module, {:group, _site_ids, sites} = scope, opts, pages_left) do
    with {:ok, %{items: items, next: next}} <- guarded(fn -> module.list_remote(opts) end),
         {:ok, holders} <-
           ProviderHoldings.sites_holding(module.library_meta_path(), Enum.map(items, & &1.remote_id), sites) do
      items = Enum.filter(items, &shared?(scope, holders[&1.remote_id]))

      if (items == [] and next) && pages_left > 1,
        do: list_page(module, scope, Keyword.put(opts, :cursor, next), pages_left - 1),
        else: {:ok, %{items: items, next: next}}
    end
  end

  @doc """
  Adds the remote video to Brando's library and returns its record — or the
  record that already holds it.

  ## Options

    * `:config_target` — stored on a new record, as an upload would
  """
  @spec import(atom(), String.t(), Brando.Users.User.t(), keyword()) :: {:ok, Video.t()} | {:error, term()}
  def import(strategy, remote_id, user, opts \\ []) when is_binary(remote_id) do
    with :ok <- Brando.Authorization.Media.authorize(user, :video),
         scope = scope(),
         {:ok, module} <- provider(strategy, scope),
         :ok <- may_add(module, scope, remote_id) do
      find_or_import(module, remote_id, user, opts)
    end
  end

  # The listing's filter, again: the event names any remote id. A video the
  # site may not see is reported as one the provider does not have.
  defp may_add(_module, :account, _remote_id), do: :ok

  defp may_add(module, {:group, _site_ids, sites} = scope, remote_id) do
    case ProviderHoldings.sites_holding(module.library_meta_path(), [remote_id], sites) do
      {:ok, holders} -> if shared?(scope, holders[remote_id]), do: :ok, else: {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp shared?(_scope, nil), do: true
  defp shared?({:group, site_ids, _sites}, holders), do: not MapSet.disjoint?(holders, site_ids)

  # What the current site may see of the provider accounts: all of it without
  # tenancy or with one site; with several, the videos its group holds and
  # those no site holds, or nothing for a site in no group. Read from the
  # registry, not the node's cache: a group just left must not still share.
  defp scope do
    if Tenant.mode() == :multi, do: site_scope(Tenant.current_site_key()), else: :account
  end

  defp site_scope(nil), do: :isolated

  defp site_scope(site_key) do
    sites = Registry.list_sites()

    case Enum.find(sites, &(&1.key == site_key)) do
      %{provider_library_group: group} when is_binary(group) and group != "" ->
        {:group, for(site <- sites, site.provider_library_group == group, into: MapSet.new(), do: site.id), sites}

      _isolated ->
        :isolated
    end
  end

  defp find_or_import(module, remote_id, user, opts) do
    case Brando.Videos.get_video_by_meta(module.library_meta_path(), remote_id) do
      %Video{} = video -> {:ok, video}
      nil -> guarded(fn -> module.import_remote(remote_id, user, opts) end)
    end
  end

  @doc "Whether the record was added from a provider library rather than uploaded."
  @spec imported?(Video.t()) :: boolean()
  def imported?(%Video{meta: %{"imported" => true}}), do: true
  def imported?(_video), do: false

  defp provider(strategy, scope) do
    case Enum.find(providers(scope), &(&1.strategy == strategy)) do
      %{strategy: strategy} ->
        {_strategy, module, _label} = List.keyfind(@providers, strategy, 0)
        {:ok, module}

      nil ->
        {:error, {:unknown_strategy, strategy}}
    end
  end

  defp searchable?(module) do
    function_exported?(module, :library_searchable?, 0) and module.library_searchable?()
  end

  defp existing_video_ids(_path, []), do: %{}

  defp existing_video_ids(path, remote_ids) do
    keys = String.split(path, ".")

    from(v in Video,
      where: is_nil(v.deleted_at) and fragment("?#>>? = ANY(?)", v.meta, ^keys, ^remote_ids),
      select: {fragment("?#>>?", v.meta, ^keys), v.id}
    )
    |> Brando.Repo.all()
    |> Map.new()
  end

  # Same contract as `Brando.Videos.Uploader.initiate_upload/3`: the callers are
  # LiveViews holding an editor's unsaved work, so a provider client raising —
  # a decode error, a transport failure — comes back as an error tuple.
  defp guarded(fun) do
    fun.()
  rescue
    exception ->
      Logger.error("Video provider library call raised: " <> Exception.format(:error, exception, __STACKTRACE__))
      {:error, :provider_error}
  end
end
