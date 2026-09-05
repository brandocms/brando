defmodule Brando.Content.SharedLibrary do
  @moduledoc """
  Resolves Brando's shared module, container, and palette library.

  Shared entries live in `public`. Site-specific entries and overrides live in
  the active environment schema. Blocks carry an explicit origin so an integer
  ID collision between schemas can never change which entry is selected.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Content.Container
  alias Brando.Content.Module
  alias Brando.Content.Palette
  alias Brando.Content.SharedLibrary.Cache
  alias Brando.Content.SiteEnabledContainer
  alias Brando.Content.SiteEnabledModule
  alias Brando.Content.SiteEnabledPalette
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Ecto.Changeset

  @public_opts [prefix: "public"]
  @kinds [:module, :container, :palette]

  # A function, not a module attribute. `Ref.preloads/0` resolved inside an
  # attribute is a compile-time call into a Blueprint schema, which puts this
  # module inside Blueprint's compile-connected component — see issue #2737. The
  # map is small and built per lookup; the lookups are not hot.
  defp definitions do
    %{
      module: %{
        schema: Module,
        access_schema: SiteEnabledModule,
        access_field: :module_id,
        block_field: :module_id,
        block_origin_field: :module_origin,
        source_field: :source_module_id,
        preloads: [:vars, refs: Brando.Content.Ref.preloads()]
      },
      container: %{
        schema: Container,
        access_schema: SiteEnabledContainer,
        access_field: :container_id,
        block_field: :container_id,
        block_origin_field: :container_origin,
        source_field: :source_container_id,
        preloads: []
      },
      palette: %{
        schema: Palette,
        access_schema: SiteEnabledPalette,
        access_field: :palette_id,
        block_field: :palette_id,
        block_origin_field: :palette_origin,
        source_field: :source_palette_id,
        preloads: []
      }
    }
  end

  @doc "Returns the public IDs enabled for `site` and `kind`."
  def enabled_ids(%Site{id: site_id}, kind) when kind in @kinds do
    case Cache.get(site_id, kind) do
      %MapSet{} = ids -> ids
      nil -> load_enabled_ids(site_id, kind)
    end
  end

  @doc "Atomically replaces one site's allowlist for a library kind."
  def set_enabled(%Site{} = site, kind, ids) when kind in @kinds and is_list(ids) do
    definition = definition(kind)
    ids = ids |> Enum.map(&normalize_id!/1) |> Enum.uniq() |> Enum.sort()

    with :ok <- validate_shared_ids(definition.schema, ids),
         {:ok, _result} <- replace_access_rows(site.id, definition, ids) do
      Cache.put(site.id, kind, ids)
      :ok
    end
  end

  def enable(%Site{} = site, kind, id) when kind in @kinds do
    ids = [normalize_id!(id) | MapSet.to_list(enabled_ids(site, kind))]
    set_enabled(site, kind, ids)
  end

  def disable(%Site{} = site, kind, id) when kind in @kinds do
    id = normalize_id!(id)
    ids = site |> enabled_ids(kind) |> MapSet.delete(id) |> MapSet.to_list()
    set_enabled(site, kind, ids)
  end

  def enabled?(%Site{} = site, kind, id) when kind in @kinds do
    MapSet.member?(enabled_ids(site, kind), normalize_id!(id))
  end

  @doc "Lists every non-deleted public entry in a shared library."
  def list_shared(kind) when kind in @kinds do
    definition = definition(kind)

    definition.schema
    |> active_query()
    |> Repo.all(@public_opts)
    |> Repo.preload(definition.preloads, @public_opts)
    |> Enum.map(&mark_entry(&1, :shared, false))
  end

  @doc "Gets one public shared-library entry with its editing associations preloaded."
  def get_shared(kind, id) when kind in @kinds do
    kind
    |> get_public(normalize_id!(id))
    |> mark_entry_or_nil(:shared, false)
  end

  @doc "Creates a versioned entry directly in the public shared library."
  def create_shared(kind, attrs, user \\ :system) when kind in @kinds and is_map(attrs) do
    definition = definition(kind)
    schema = definition.schema

    schema
    |> struct()
    |> schema.changeset(attrs, user)
    |> Repo.insert(@public_opts)
  end

  @doc "Lists site-local entries plus only the shared entries enabled for new content."
  def list_available(kind, %Site{} = site, prefix) when kind in @kinds do
    list_effective(kind, site, prefix, :enabled)
  end

  @doc """
  Lists all effective entries required to render existing content.

  Disabled shared entries stay in this result so blocks created before access
  was revoked continue to render; the picker uses `list_available/3` instead.
  """
  def list_for_rendering(kind, %Site{} = site, prefix) when kind in @kinds do
    list_effective(kind, site, prefix, :rendering)
  end

  def list_for_current_tenant(kind) when kind in @kinds do
    with prefix when is_binary(prefix) <- Tenant.current_prefix(),
         site_key when is_binary(site_key) <- Tenant.current_site_key(),
         %Site{} = site <- Registry.get_site_by_key(site_key) do
      list_for_rendering(kind, site, prefix)
    else
      _no_tenant -> list_local(kind, nil)
    end
  end

  @doc """
  Resolves an origin-qualified reference. Shared reads allow disabled IDs
  by default for backwards-compatible rendering; pass `require_enabled: true`
  for new-content workflows.
  """
  def get(kind, id, origin, %Site{} = site, prefix, opts \\ []) when kind in @kinds do
    id = normalize_id!(id)

    case normalize_origin(origin) do
      :local -> get_local(kind, id, prefix)
      :shared -> get_shared(kind, id, site, prefix, opts)
    end
  end

  @doc "Compatibility resolver matching the Phase 4 tenant-first contract."
  def get(kind, id, %Site{} = site, prefix) when kind in @kinds do
    id = normalize_id!(id)
    get_local(kind, id, prefix) || get_shared(kind, id, site, prefix, require_enabled: true)
  end

  def get_for_current_tenant(kind, id, origin \\ :local) when kind in @kinds do
    with prefix when is_binary(prefix) <- Tenant.current_prefix(),
         site_key when is_binary(site_key) <- Tenant.current_site_key(),
         %Site{} = site <- Registry.get_site_by_key(site_key) do
      get(kind, id, origin, site, prefix)
    else
      _no_tenant -> get_local(kind, normalize_id!(id), nil)
    end
  end

  @doc "Copies a shared entry into the tenant schema as an override."
  def customize(kind, id, %Site{} = site, prefix, user \\ :system) when kind in @kinds do
    id = normalize_id!(id)

    cond do
      not enabled?(site, kind, id) ->
        {:error, :not_enabled}

      override = get_override(kind, id, prefix) ->
        {:ok, override}

      shared = get_public(kind, id) ->
        create_override(kind, shared, prefix, user)

      true ->
        {:error, :not_found}
    end
  end

  @doc "Deletes a tenant override; origin-qualified blocks immediately use shared again."
  def reset(kind, id, %Site{}, prefix) when kind in @kinds do
    case get_override(kind, normalize_id!(id), prefix) do
      nil -> :ok
      override -> override |> Repo.delete(prefix: prefix) |> result_to_ok()
    end
  end

  @doc "Destructively replaces an override with the current shared version."
  def accept_update(kind, id, %Site{}, prefix, user \\ :system) when kind in @kinds do
    id = normalize_id!(id)

    with override when not is_nil(override) <- get_override(kind, id, prefix),
         shared when not is_nil(shared) <- get_public(kind, id) do
      replace_override(kind, override, shared, prefix, user)
    else
      nil -> {:error, :not_found}
    end
  end

  @doc "Acknowledges the current shared version without replacing local changes."
  def dismiss_update(kind, id, %Site{}, prefix) when kind in @kinds do
    with override when not is_nil(override) <- get_override(kind, normalize_id!(id), prefix),
         shared when not is_nil(shared) <- get_public(kind, normalize_id!(id)) do
      override
      |> Changeset.change(acknowledged_version: shared.version)
      |> Repo.update(prefix: prefix)
    else
      nil -> {:error, :not_found}
    end
  end

  @doc "Updates a public library entry and bumps its meaningful version."
  def update_shared(kind, id, attrs_or_changeset, user \\ :system)

  def update_shared(kind, id, %Changeset{} = changeset, _user) when kind in @kinds do
    id = normalize_id!(id)

    if changeset.data.id == id and changeset.data.__struct__ == definition(kind).schema do
      changeset
      |> Changeset.put_change(:version, (changeset.data.version || 1) + 1)
      |> Changeset.validate_required([:version_note])
      |> Repo.update(@public_opts)
      |> after_shared_update(kind)
    else
      {:error, :invalid_shared_changeset}
    end
  end

  def update_shared(kind, id, attrs, user) when kind in @kinds and is_map(attrs) do
    definition = definition(kind)
    schema = definition.schema

    case get_public(kind, normalize_id!(id)) do
      nil ->
        {:error, :not_found}

      shared ->
        attrs =
          attrs
          |> Map.put(version_key(attrs), (shared.version || 1) + 1)
          |> Map.delete(opposite_version_key(attrs))

        result =
          shared
          |> schema.changeset(attrs, user)
          |> Changeset.validate_required([:version_note])
          |> Repo.update(@public_opts)

        after_shared_update(result, kind)
    end
  end

  @doc "Returns enabled and overridden sites for impact analysis."
  def usage(kind, id) when kind in @kinds do
    id = normalize_id!(id)

    Registry.list_sites()
    |> Enum.map(&usage_for_site(&1, kind, id))
    |> Enum.reject(&(!&1.enabled and &1.overridden_environments == [] and &1.referenced_environments == []))
  end

  @doc "Returns field-level changes between a tenant override and its current shared source."
  def diff(kind, id, %Site{}, prefix) when kind in @kinds do
    id = normalize_id!(id)

    with override when not is_nil(override) <- get_override(kind, id, prefix),
         shared when not is_nil(shared) <- get_public(kind, id) do
      definition = definition(kind)

      fields =
        definition.schema.__schema__(:fields) --
          [
            :id,
            :inserted_at,
            :updated_at,
            :deleted_at,
            :version,
            :version_note,
            :source_version,
            :acknowledged_version,
            definition.source_field
          ]

      {:ok,
       fields
       |> Enum.reduce(%{}, fn field, changes ->
         shared_value = Map.get(shared, field)
         override_value = Map.get(override, field)

         if shared_value == override_value do
           changes
         else
           Map.put(changes, field, %{shared: shared_value, override: override_value})
         end
       end)}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc "Prevents deleting a shared entry while any site can still use it."
  def delete_shared(kind, id) when kind in @kinds do
    id = normalize_id!(id)

    case usage(kind, id) do
      [] ->
        case get_public(kind, id) do
          nil -> {:error, :not_found}
          entry -> Repo.delete(entry, @public_opts)
        end

      usages ->
        {:error, {:shared_item_in_use, usages}}
    end
  end

  def reference(value) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      [origin, id] when origin in ["local", "shared"] ->
        {normalize_origin(origin), normalize_id!(id)}

      [id] ->
        {:local, normalize_id!(id)}
    end
  end

  def reference(id) when is_integer(id), do: {:local, id}
  def reference({origin, id}), do: {normalize_origin(origin), normalize_id!(id)}
  def encode_reference(origin, id), do: "#{normalize_origin(origin)}:#{normalize_id!(id)}"

  defp list_effective(kind, site, prefix, shared_scope) do
    definition = definition(kind)
    locals = list_local(kind, prefix)
    {site_specific, overrides} = Enum.split_with(locals, &is_nil(Map.get(&1, definition.source_field)))
    overrides_by_source = Map.new(overrides, &{Map.fetch!(&1, definition.source_field), &1})

    shared_ids =
      case shared_scope do
        :enabled -> enabled_ids(site, kind)
        :rendering -> MapSet.union(enabled_ids(site, kind), referenced_shared_ids(kind, prefix))
      end

    shared =
      kind
      |> list_shared()
      |> maybe_filter_ids(shared_ids)
      |> Enum.map(fn entry ->
        case overrides_by_source[entry.id] do
          nil -> mark_entry(entry, :shared, false)
          override -> effective_override(override, entry)
        end
      end)

    Enum.map(site_specific, &mark_entry(&1, :local, false)) ++ shared
  end

  defp list_local(kind, prefix) do
    definition = definition(kind)
    opts = if is_binary(prefix), do: [prefix: prefix], else: []

    definition.schema
    |> active_query()
    |> Repo.all(opts)
    |> Repo.preload(definition.preloads, opts)
  end

  defp get_local(kind, id, prefix) do
    definition = definition(kind)
    opts = if is_binary(prefix), do: [prefix: prefix], else: []

    definition.schema
    |> Repo.get(id, opts)
    |> preload_one(definition.preloads, opts)
    |> mark_entry_or_nil(:local, false)
  end

  defp get_shared(kind, id, site, prefix, opts) do
    if Keyword.get(opts, :require_enabled, false) and not enabled?(site, kind, id) do
      nil
    else
      case {get_override(kind, id, prefix), get_public(kind, id)} do
        {nil, nil} -> nil
        {nil, shared} -> mark_entry(shared, :shared, false)
        {override, nil} -> mark_entry(override, :shared, false)
        {override, shared} -> effective_override(override, shared)
      end
    end
  end

  defp get_override(kind, source_id, prefix) do
    definition = definition(kind)
    opts = [prefix: prefix]

    from(entry in definition.schema,
      where: field(entry, ^definition.source_field) == ^source_id and is_nil(entry.deleted_at),
      limit: 1
    )
    |> Repo.one(opts)
    |> preload_one(definition.preloads, opts)
  end

  defp get_public(kind, id) do
    definition = definition(kind)

    definition.schema
    |> Repo.get(id, @public_opts)
    |> preload_one(definition.preloads, @public_opts)
  end

  defp shared_reference_exists?(kind, id, prefix) do
    definition = definition(kind)

    query =
      from block in Block,
        where:
          field(block, ^definition.block_field) == ^id and
            field(block, ^definition.block_origin_field) == :shared,
        select: 1,
        limit: 1

    not is_nil(Repo.one(query, prefix: prefix))
  end

  defp referenced_shared_ids(kind, prefix) do
    definition = definition(kind)

    from(block in Block,
      where:
        field(block, ^definition.block_origin_field) == :shared and
          not is_nil(field(block, ^definition.block_field)),
      select: field(block, ^definition.block_field),
      distinct: true
    )
    |> Repo.all(prefix: prefix)
    |> MapSet.new()
  end

  defp rerender_shared(kind, id) do
    Enum.each(Registry.list_sites(), &rerender_site(&1, kind, id))
  end

  defp rerender_site(site, kind, id) do
    Enum.each(site.environments, &rerender_environment(site, &1, kind, id))
  end

  defp rerender_environment(site, environment, kind, id) do
    prefix = Tenant.prefix(site, environment)
    Tenant.with_prefix(prefix, fn -> rerender_kind(kind, id) end)
  end

  defp rerender_kind(:module, id), do: Blocks.render_entries_with_module_id(id, :shared)
  defp rerender_kind(:container, id), do: Blocks.render_entries_with_container_id(id, :shared)
  defp rerender_kind(:palette, id), do: Blocks.render_entries_with_palette_id(id, :shared)

  defp usage_for_site(site, kind, id) do
    {overridden, referenced} =
      Enum.reduce(site.environments, {[], []}, &collect_environment_usage(&1, &2, site, kind, id))

    %{
      site: site,
      enabled: enabled?(site, kind, id),
      overridden_environments: Enum.reverse(overridden),
      referenced_environments: Enum.reverse(referenced)
    }
  end

  defp collect_environment_usage(environment, {overridden, referenced}, site, kind, id) do
    prefix = Tenant.prefix(site, environment)

    {
      prepend_if(overridden, environment.key, get_override(kind, id, prefix)),
      prepend_if(referenced, environment.key, shared_reference_exists?(kind, id, prefix))
    }
  end

  defp prepend_if(values, value, present) when present not in [false, nil], do: [value | values]
  defp prepend_if(values, _value, _missing), do: values

  defp replace_override(kind, override, shared, prefix, user) do
    Repo.transaction(fn ->
      with {:ok, _deleted} <- Repo.delete(override, prefix: prefix),
           {:ok, replacement} <- create_override(kind, shared, prefix, user) do
        replacement
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp after_shared_update({:ok, updated} = result, kind) do
    rerender_shared(kind, updated.id)
    result
  end

  defp after_shared_update(result, _kind), do: result

  defp create_override(kind, shared, prefix, user) do
    definition = definition(kind)
    schema = definition.schema

    attrs =
      shared
      |> copy_fields(definition)
      |> Map.put(definition.source_field, shared.id)
      |> Map.put(:source_version, shared.version || 1)
      |> Map.put(:acknowledged_version, shared.version || 1)
      |> Map.put(:version, 1)
      |> put_copy_associations(kind, shared)

    struct(schema)
    |> schema.changeset(attrs, user)
    |> Changeset.unique_constraint(definition.source_field)
    |> Repo.insert(prefix: prefix)
  end

  defp copy_fields(shared, definition) do
    excluded =
      [
        :id,
        :inserted_at,
        :updated_at,
        :deleted_at,
        :version,
        :version_note,
        :source_version,
        :acknowledged_version,
        definition.source_field
      ]

    shared
    |> Map.from_struct()
    |> Map.take(definition.schema.__schema__(:fields))
    |> Map.drop(excluded)
  end

  defp put_copy_associations(attrs, :module, shared) do
    attrs
    |> Map.put(:vars, Enum.map(loaded_list(shared.vars), &copy_assoc(&1, [:module_id])))
    |> Map.put(:refs, Enum.map(loaded_list(shared.refs), &copy_assoc(&1, [:module_id])))
  end

  defp put_copy_associations(attrs, _kind, _shared), do: attrs

  defp copy_assoc(entry, owner_fields) do
    entry
    |> Map.from_struct()
    |> Map.take(entry.__struct__.__schema__(:fields))
    |> Map.drop([:id, :inserted_at, :updated_at, :deleted_at, :creator_id] ++ owner_fields)
    |> Brando.Utils.map_from_struct()
  end

  defp effective_override(override, shared) do
    shared_version = shared.version || 1

    update_available =
      (override.source_version || 0) < shared_version and
        (override.acknowledged_version || 0) < shared_version

    override
    |> Map.put(:id, shared.id)
    |> Map.put(:override_id, override.id)
    |> mark_entry(:shared, update_available)
  end

  defp mark_entry(entry, origin, update_available) do
    entry
    |> Map.put(:library_origin, origin)
    |> Map.put(:update_available, update_available)
  end

  defp mark_entry_or_nil(nil, _origin, _update_available), do: nil
  defp mark_entry_or_nil(entry, origin, update_available), do: mark_entry(entry, origin, update_available)

  defp active_query(schema), do: from(entry in schema, where: is_nil(entry.deleted_at))

  defp maybe_filter_ids(entries, %MapSet{} = ids), do: Enum.filter(entries, &MapSet.member?(ids, &1.id))

  defp validate_shared_ids(_schema, []), do: :ok

  defp validate_shared_ids(schema, ids) do
    found =
      from(entry in schema, where: entry.id in ^ids and is_nil(entry.deleted_at), select: entry.id)
      |> Repo.all(@public_opts)
      |> MapSet.new()

    missing = Enum.reject(ids, &MapSet.member?(found, &1))
    if missing == [], do: :ok, else: {:error, {:shared_items_not_found, missing}}
  end

  defp replace_access_rows(site_id, definition, ids) do
    Repo.transaction(fn ->
      from(access in definition.access_schema, where: access.site_id == ^site_id)
      |> Repo.delete_all(@public_opts)

      now = DateTime.utc_now()

      rows =
        Enum.map(ids, fn id ->
          %{definition.access_field => id, site_id: site_id, inserted_at: now, updated_at: now}
        end)

      Repo.insert_all(definition.access_schema, rows, @public_opts)
    end)
  end

  defp load_enabled_ids(site_id, kind) do
    definition = definition(kind)

    ids =
      from(access in definition.access_schema,
        where: access.site_id == ^site_id,
        select: field(access, ^definition.access_field)
      )
      |> Repo.all(@public_opts)

    Cache.put(site_id, kind, ids)
    MapSet.new(ids)
  end

  defp preload_one(nil, _preloads, _opts), do: nil
  defp preload_one(entry, [], _opts), do: entry
  defp preload_one(entry, preloads, opts), do: Repo.preload(entry, preloads, opts)

  defp loaded_list(%Ecto.Association.NotLoaded{}), do: []
  defp loaded_list(nil), do: []
  defp loaded_list(list), do: list

  defp result_to_ok({:ok, _entry}), do: :ok
  defp result_to_ok({:error, _changeset} = error), do: error

  defp definition(kind), do: Map.fetch!(definitions(), kind)

  defp normalize_origin(origin) when origin in [:local, "local", nil], do: :local
  defp normalize_origin(origin) when origin in [:shared, "shared"], do: :shared
  defp normalize_origin(origin), do: raise(ArgumentError, "invalid library origin: #{inspect(origin)}")

  defp normalize_id!(id) when is_integer(id) and id > 0, do: id

  defp normalize_id!(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> raise ArgumentError, "invalid shared library id: #{inspect(id)}"
    end
  end

  defp normalize_id!(id), do: raise(ArgumentError, "invalid shared library id: #{inspect(id)}")

  defp version_key(attrs) do
    if Enum.all?(Map.keys(attrs), &is_binary/1), do: "version", else: :version
  end

  defp opposite_version_key(attrs) do
    if Enum.all?(Map.keys(attrs), &is_binary/1), do: :version, else: "version"
  end
end
