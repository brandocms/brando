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

  With `:single` or `:none` tenancy, the whole account is listed.

  ## One record per remote video

  Adding a video that already has a record — uploaded through Brando, or added
  before — returns that record instead of creating another. So does adding a
  Mux asset whose upload the site started and Mux has not reported yet: the
  upload's record has only the upload id, which the listing matches too. Two
  records for one remote video would mean deleting either could remove the
  video from under the other, and the provider webhooks look a video up by
  its remote id and expect one answer.

  Adding a video whose record was deleted and waits for its purge restores
  that record, for an editor who may restore it: the purge would otherwise
  delete at the provider the video a new record plays. A record deleted with
  `delete_remote_on: :on_delete` is not restored, as its video may be gone
  at the provider; the video is added as a new record if the provider still
  has it.

  Restoring a deleted record from the trash is refused while the
  environment has a live record of the same remote video
  (`guard_restore/3`): delete that one first, or use it instead.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Videos.ProviderHoldings
  alias Brando.Videos.Uploader
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
      existing = existing_video_ids(module.library_meta_path(), items)

      {:ok,
       %{
         page
         | items: Enum.map(items, &(&1 |> Map.delete(:holding_keys) |> Map.put(:video_id, existing[&1.remote_id])))
       }}
    end
  end

  defp list_page(module, :account, opts, _pages_left), do: guarded(fn -> module.list_remote(opts) end)

  defp list_page(module, {:group, _site_ids, sites} = scope, opts, pages_left) do
    with {:ok, %{items: items, next: next}} <- guarded(fn -> module.list_remote(opts) end),
         {:ok, holders} <-
           ProviderHoldings.sites_holding(module.library_meta_path(), Enum.map(items, &holding/1), sites) do
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
         {:ok, module} <- provider(strategy, scope) do
      import_in_scope(module, scope, remote_id, user, opts)
    end
  end

  # The site's own record first, by the provider's id: that needs no call to
  # the provider. Then by the other keys a record may hold the video at, such
  # as the site's own Mux upload still waiting for its asset.
  defp import_in_scope(module, scope, remote_id, user, opts) do
    path = module.library_meta_path()

    with nil <- existing_video(path, remote_id, []),
         {:ok, keys} <- holding_keys(module, remote_id),
         nil <- if(keys != [], do: existing_video(path, remote_id, keys)) do
      add(module, scope, {remote_id, keys}, user, opts)
    else
      %Video{} = video -> {:ok, video}
      {:error, _reason} = error -> error
    end
  end

  # A delete or a purge of the same video at the provider waits, and this
  # waits for one in progress (`Brando.Videos.ProviderHoldings.with_video_lock/3`).
  defp add(module, scope, {remote_id, _keys} = holding, user, opts) do
    ProviderHoldings.with_video_lock(module.library_meta_path(), remote_id, fn ->
      with :ok <- may_add(module, scope, holding), do: find_or_import(module, holding, user, opts)
    end)
  end

  # The listing's filter, again: the event names any remote id. A video the
  # site may not see is reported as one the provider does not have.
  defp may_add(_module, :account, _holding), do: :ok

  defp may_add(module, {:group, _site_ids, sites} = scope, {remote_id, _keys} = holding) do
    case ProviderHoldings.sites_holding(module.library_meta_path(), [holding], sites) do
      {:ok, holders} -> if shared?(scope, holders[remote_id]), do: :ok, else: {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp holding_keys(module, remote_id) do
    if function_exported?(module, :library_holding_keys, 1),
      do: guarded(fn -> module.library_holding_keys(remote_id) end),
      else: {:ok, []}
  end

  defp holding(%{remote_id: remote_id} = item), do: {remote_id, Map.get(item, :holding_keys, [])}

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

  defp find_or_import(module, {remote_id, keys}, user, opts) do
    path = module.library_meta_path()

    with nil <- existing_video(path, remote_id, keys),
         nil <- restore_deleted(path, remote_id, user) do
      guarded(fn -> module.import_remote(remote_id, user, opts) end)
    else
      %Video{} = video -> {:ok, video}
    end
  end

  # The environment's deleted record of the video, waiting for its purge,
  # comes back rather than a second record: its purge would delete at the
  # provider the video the second one plays. Not a record deleted with
  # `delete_remote_on: :on_delete`, whose video the provider was asked to
  # delete then: the provider is asked for it again, and a second record
  # made, which that purge leaves alone. Nor one the user may not restore:
  # the second record then keeps the video at the provider, as a live record
  # of the environment does (`Brando.Videos.Uploader.delete_remote/1`).
  defp restore_deleted(path, remote_id, user) do
    keys = String.split(path, ".")

    from(v in Video,
      where: not is_nil(v.deleted_at) and fragment("?#>>? = ?", v.meta, ^keys, ^remote_id),
      order_by: [desc: v.deleted_at, desc: v.id]
    )
    |> Brando.Repo.all()
    |> Enum.find(&(Uploader.get_delete_timing(&1) != :on_delete))
    |> case do
      nil ->
        nil

      video ->
        restore(user, video)
    end
  end

  # A record never deleted at the provider (imported, or `delete_remote_on:
  # false`) is purged without the video's lock, so it may be gone since it
  # was read (`{:error, :not_found}`): the video is then added as a new
  # record.
  defp restore(user, video) do
    case Boundary.restore(user, video) do
      {:ok, restored} -> restored
      {:error, _reason} -> nil
    end
  end

  # The current environment's record of the remote video: by the provider's
  # id at `path`, or else by one of `keys`.
  defp existing_video(path, remote_id, keys) do
    Enum.find_value([{path, remote_id} | keys], fn {key_path, value} ->
      keys = String.split(key_path, ".")

      from(v in Video,
        where: is_nil(v.deleted_at) and fragment("?#>>? = ?", v.meta, ^keys, ^value),
        order_by: v.id,
        limit: 1
      )
      |> Brando.Repo.one()
    end)
  end

  @doc """
  Runs `fun` holding the lock of `video`'s remote video
  (`Brando.Videos.ProviderHoldings.with_video_lock/3`), so an add of the same
  video from the library, or its purge, does not land while it runs. A video
  with no remote id has no lock, and `fun` just runs.
  `Brando.Authorization.Boundary.restore/2` takes it before its transaction
  opens and calls `guard_restore/3` inside.
  """
  @spec with_restore_lock(Video.t(), (-> result)) :: result | {:error, :busy | :holdings_unavailable}
        when result: term()
  def with_restore_lock(%Video{} = video, fun) do
    case Uploader.library_remote_id(video) do
      {module, remote_id} -> ProviderHoldings.with_video_lock(module.library_meta_path(), remote_id, fun)
      nil -> fun.()
    end
  end

  @doc """
  Runs `restore` with the deleted `video` as stored now, read again under
  `with_restore_lock/2`, unless:

    * it is gone, purged since it was read, or before `restore` writes it:
      `{:error, :not_found}`;
    * it is live, restored since it was read: `{:ok, video}`, as it is,
      and `restore` does not run;
    * the current environment has a live record of the same remote video:
      `{:error, {:recorded_here, live}}`, with that record if `user` may read
      it and `nil` otherwise. Every tenancy mode keeps one live record per
      remote video and environment, as an add from the library does.
  """
  @spec guard_restore(term(), Video.t(), (Video.t() -> result)) :: result | {:ok, Video.t()} | {:error, term()}
        when result: term()
  def guard_restore(user, %Video{id: id}, restore) do
    case Brando.Repo.get(Video, id) do
      nil -> {:error, :not_found}
      %Video{deleted_at: nil} = video -> {:ok, video}
      video -> video |> live_record() |> restore_unless_live(user, fn -> restore.(video) end)
    end
  end

  defp live_record(video) do
    case Uploader.library_remote_id(video) do
      {module, remote_id} -> ProviderHoldings.recorded_here(module.library_meta_path(), remote_id, video.id)
      nil -> nil
    end
  end

  # A record the purge deletes without the video's lock (imported, or not
  # deleted at the provider on purge) may go between the read and the write.
  # With groups authorization, the change's check locks the row first and
  # refuses one that is gone (`{:error, :forbidden}`).
  defp restore_unless_live(nil, _user, restore) do
    restore.()
  rescue
    Ecto.StaleEntryError -> {:error, :not_found}
  end

  defp restore_unless_live(live, user, _restore),
    do: {:error, {:recorded_here, if(Boundary.authorize(user, :read, live) == :ok, do: live)}}

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

  # The ids of the records holding the items, by remote id: a record with the
  # provider's id at `path` first, else one with one of the item's
  # `:holding_keys`.
  defp existing_video_ids(_path, []), do: %{}

  defp existing_video_ids(path, items) do
    lookups = [{path, Enum.map(items, &{&1.remote_id, &1.remote_id})} | key_lookups(items)]

    Enum.reduce(lookups, %{}, fn {key_path, pairs}, existing ->
      remote_ids = Map.new(pairs)
      keys = String.split(key_path, ".")

      from(v in Video,
        where: is_nil(v.deleted_at) and fragment("?#>>? = ANY(?)", v.meta, ^keys, ^Map.keys(remote_ids)),
        select: {fragment("?#>>?", v.meta, ^keys), v.id},
        order_by: v.id
      )
      |> Brando.Repo.all()
      |> Enum.reduce(existing, fn {value, id}, existing -> Map.put_new(existing, remote_ids[value], id) end)
    end)
  end

  # `{key_path, [{value, remote_id}]}` for the items' holding keys.
  defp key_lookups(items) do
    for item <- items, {key_path, value} <- Map.get(item, :holding_keys, []), is_binary(value) do
      {key_path, {value, item.remote_id}}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.to_list()
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
