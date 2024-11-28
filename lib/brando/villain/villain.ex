# credo:disable-for-this-file
defmodule Brando.Villain do
  use Brando.Query
  import Ecto.Query
  alias Ecto.Changeset
  alias Liquex.Context
  alias Brando.Cache
  alias Brando.Content
  alias Brando.Pages
  alias Brando.Trait
  alias Brando.Utils
  alias Brando.Villain.Blocks

  @type changeset :: Ecto.Changeset.t()

  @module_cache_ttl (Brando.config(:env) in [:e2e, :test] && %{preload: [:vars]}) ||
                      %{cache: {:ttl, :infinite}, preload: [:vars]}
  @container_cache_ttl (Brando.config(:env) in [:e2e, :test] && %{preload: [:palette]}) ||
                         %{cache: {:ttl, :infinite}, preload: [:palette]}
  @palette_cache_ttl (Brando.config(:env) in [:e2e, :test] && %{}) || %{cache: {:ttl, :infinite}}
  @fragment_cache_ttl (Brando.config(:env) in [:e2e, :test] && %{}) || %{cache: {:ttl, :infinite}}

  @doc """
  Parse blocks

  Delegates to the parser module configured in the otp_app's brando.exs.
  Renders to HTML.
  """
  def parse(entry_blocks_list, entry \\ nil, opts \\ [])
  def parse([], _, _), do: ""
  def parse("", _, _), do: ""
  def parse(nil, _, _), do: ""

  def parse(entry_blocks_list, entry, opts) do
    start = System.monotonic_time()
    opts_map = Enum.into(opts, %{})
    parser = Brando.config(Brando.Villain)[:parser]

    {:ok, modules} = Content.list_modules(@module_cache_ttl)
    {:ok, containers} = Content.list_containers(@container_cache_ttl)
    {:ok, palettes} = Content.list_palettes(@palette_cache_ttl)
    {:ok, fragments} = Pages.list_fragments(@fragment_cache_ttl)

    entry = maybe_put_timestamps(entry)

    context =
      entry
      |> Brando.Villain.get_base_context()
      |> add_request_to_context(opts_map)
      |> add_url_to_context(entry)

    opts_map =
      opts_map
      |> Map.put(:context, context)
      |> Map.put(:modules, modules)
      |> Map.put(:containers, containers)
      |> Map.put(:palettes, palettes)
      |> Map.put(:fragments, fragments)

    html =
      entry_blocks_list
      |> Enum.reduce([], fn
        nil, acc -> acc
        %{block: %{marked_as_deleted: true}}, acc -> acc
        %{block: block}, acc -> [parse_node(parser, block, opts_map) | acc]
      end)
      |> Enum.reverse()
      |> Enum.join()

    output = parse_and_render(html, context)

    :telemetry.execute([:brando, :villain, :parse_and_render], %{
      duration: System.monotonic_time() - start
    })

    output
  end

  def render_block(block, entry, opts \\ [])
  def render_block(%{active: false}, _entry, _opts), do: ""
  def render_block(%{marked_as_deleted: true}, _entry, _opts), do: ""

  def render_block(%Content.Block{} = block, entry, opts) do
    opts_map = Enum.into(opts, %{})
    parser = Brando.config(Brando.Villain)[:parser]

    {:ok, modules} = Content.list_modules(@module_cache_ttl)
    {:ok, containers} = Content.list_containers(@container_cache_ttl)
    {:ok, palettes} = Content.list_palettes(@palette_cache_ttl)
    {:ok, fragments} = Pages.list_fragments(@fragment_cache_ttl)

    entry = maybe_put_timestamps(entry)

    context =
      entry
      |> Brando.Villain.get_base_context()
      |> add_request_to_context(opts_map)
      |> add_url_to_context(entry)

    opts_map =
      opts_map
      |> Map.put(:context, context)
      |> Map.put(:modules, modules)
      |> Map.put(:containers, containers)
      |> Map.put(:palettes, palettes)
      |> Map.put(:fragments, fragments)

    parser
    |> parse_node(block, opts_map)
    |> parse_and_render(context)
  end

  def render_block(%{block: block} = _entry_block, entry, opts) do
    render_block(block, entry, opts)
  end

  defp add_request_to_context(ctx, %{conn: conn}) do
    request = %{
      params: conn.path_params,
      url: conn.request_path
    }

    add_to_context(ctx, "request", request)
  end

  defp add_request_to_context(ctx, _), do: ctx

  defp add_url_to_context(ctx, entry) do
    add_to_context(ctx, "url", Brando.HTML.absolute_url(entry))
  end

  defp parse_node(parser, block, opts_map) do
    type_atom = if block.type == :module_entry, do: :module, else: block.type

    if not is_atom(type_atom) or is_nil(type_atom) do
      raise """
      Expected type to be an atom, got: #{inspect(type_atom)}

      Data node: #{inspect(block, pretty: true)}
      """
    end

    apply(parser, type_atom, [block, opts_map])
  end

  def get_base_context do
    locale = Gettext.get_locale(Brando.gettext())

    do_get_base_context(locale)
    |> add_to_context("language", locale)
    |> add_to_context("locale", locale)
  end

  def get_base_context(%{language: entry_language} = entry) do
    language = (entry_language in [nil, ""] && Brando.config(:default_language)) || entry_language

    do_get_base_context(to_string(language))
    |> add_to_context("language", to_string(language))
    |> add_to_context("locale", to_string(language))
    |> add_to_context("entry", entry)
  end

  def get_base_context(entry) do
    # the entry has no language set, so we fall back to the default language
    # locale = Gettext.get_locale(Brando.gettext())
    locale = Brando.config(:default_language)

    do_get_base_context(locale)
    |> add_to_context("language", locale)
    |> add_to_context("locale", locale)
    |> add_to_context("entry", entry)
  end

  defp do_get_base_context(language) do
    identity = Cache.Identity.get(language)
    globals = Cache.Globals.get(language)
    navigation = Cache.Navigation.get()

    %{}
    |> create_context()
    |> add_to_context("identity", identity)
    # |> add_to_context("configs", identity)
    |> add_to_context("links", identity)
    |> add_to_context("globals", globals)
    |> add_to_context("navigation", navigation)
  end

  def create_context(vars) do
    Context.new(
      vars,
      filter_module: Brando.web_module(Villain.Filters)
    )
  end

  # def add_to_context(context, "configs" = key, %{configs: configs}) do
  #   configs = Enum.map(configs, &{String.downcase(&1.key), &1}) |> Enum.into(%{})
  #   Context.assign(context, key, configs)
  # end

  # def add_to_context(context, "configs" = key, _) do
  #   Context.assign(context, key, %{})
  # end

  def add_to_context(context, "links" = key, %{links: links}) do
    links = Enum.map(links, &{String.downcase(&1.name), &1}) |> Enum.into(%{})
    Context.assign(context, key, links)
  end

  def add_to_context(context, "links" = key, _) do
    Context.assign(context, key, %{})
  end

  def add_to_context(context, "globals" = key, global_sets) do
    parsed_globals =
      global_sets
      |> Enum.map(fn {g_key, g_category} ->
        cat_globs =
          g_category
          |> Enum.map(fn {key, %{value: value}} -> {key, value} end)
          |> Enum.into(%{})

        {g_key, cat_globs}
      end)
      |> Enum.into(%{})

    Context.assign(context, key, parsed_globals)
  end

  def add_to_context(context, key, value) do
    Context.assign(context, key, value)
  end

  def parse_and_render(html, context) do
    liquex_parser = Brando.config(Brando.Villain)[:liquex_parser] || Brando.Villain.LiquexParser

    with {:ok, parsed_doc} <- liquex_parse(html, liquex_parser),
         {result, _} <- liquex_render([], parsed_doc, context) do
      Enum.join(result)
    else
      {:error, "expected end of string", err} ->
        require Logger

        Logger.error("""

        >>> Error parsing liquex template <<<

        #{inspect(html, pretty: true)}

        --> Expected end of string on line #{inspect(err)}

        """)

        "!!! Error parsing liquex template !!!"
    end
  end

  defp liquex_parse(html, liquex_parser) do
    Liquex.parse(html, liquex_parser)
  end

  defp liquex_render([], parsed_doc, context) do
    Liquex.Render.render!([], parsed_doc, context)
  end

  defp maybe_put_timestamps(%{inserted_at: nil} = entry) do
    datetime = DateTime.from_unix!(System.os_time(:second), :second)
    %{entry | updated_at: datetime, inserted_at: datetime}
  end

  defp maybe_put_timestamps(entry), do: entry

  @doc """
  Map out images
  """
  def map_images(images) do
    Enum.map(images, fn image ->
      sizes =
        image.sizes
        |> Enum.map(&{elem(&1, 0), Utils.media_url(elem(&1, 1))})
        |> Enum.into(%{})

      %{
        src: Utils.media_url(image.path),
        thumb: image |> Utils.img_url(:thumb) |> Utils.media_url(),
        sizes: sizes,
        dominant_color: image.dominant_color,
        formats: image.formats,
        alt: image.alt,
        title: image.title,
        credits: image.credits,
        inserted_at: image.inserted_at,
        width: image.width,
        height: image.height
      }
    end)
  end

  @doc """
  Render all entries for `schema`
  """
  def render_all_entries(schema) do
    # get all ids
    entry_ids =
      Brando.Repo.all(
        from(s in schema,
          select: s.id
        )
      )

    enqueue_entries_for_render(schema, entry_ids)
  end

  @doc """
  Rerender multiple IDS
  """
  @spec render_entries(schema :: module, ids :: [integer | binary]) :: [any()]
  def render_entries(_, []), do: []

  def render_entries(schema, ids),
    do: for(id <- ids, do: render_entry(schema, id))

  @doc """
  Rerender HTML from an ID

  ## Example

      render_entry(Pages.Page, 1)

  Will try to rerender html for page with id: 1.

  We treat page fragments special, since they need to propagate to other referencing
  pages and fragments
  """

  @spec render_entry(schema :: module, entry_id :: integer | binary) ::
          {:ok, map} | {:error, changeset}
  def render_entry(schema, id) do
    case Brando.Query.get_entry(schema, id) do
      {:ok, entry} ->
        changeset =
          entry
          |> Changeset.change()
          |> render_all_block_fields_and_add_to_changeset(schema, entry)

        case Brando.Repo.update(changeset) do
          {:ok, %Pages.Fragment{} = fragment} ->
            Brando.Cache.Query.evict({:ok, fragment})
            render_entries_with_fragment_id(fragment.id)
            {:ok, fragment}

          {:ok, result} ->
            Brando.Cache.Query.evict({:ok, result})

            {:ok, result}
        end

      {:error, _} = err ->
        require Logger

        Logger.error("""
        ==> Failed to Brando.Villain.render_entry/2

        Schema..: #{inspect(schema, pretty: true)}
        Id......: #{inspect(id, pretty: true)}

        ERROR:
        #{inspect(err, pretty: true)}

        """)

        err
    end
  end

  @doc """
  Renders all block fields for an entry and adds them to changeset
  """
  def render_all_block_fields_and_add_to_changeset(changeset, schema, entry) do
    Enum.reduce(schema.__blocks_fields__(), changeset, fn field, updated_changeset ->
      rendered_field = :"rendered_#{field.name}"
      rendered_at_field = :"rendered_#{field.name}_at"
      entry_blocks_field = :"entry_#{field.name}"
      entry_blocks = Map.get(entry, entry_blocks_field)
      rendered_html = Brando.Villain.parse(entry_blocks, entry)

      updated_changeset
      |> Changeset.put_change(rendered_field, rendered_html)
      |> update_rendered_at_field_if_changed(rendered_field, rendered_at_field)
    end)
  end

  defp update_rendered_at_field_if_changed(changeset, rendered_field, rendered_at_field) do
    if Changeset.get_change(changeset, rendered_field) do
      Changeset.put_change(
        changeset,
        rendered_at_field,
        DateTime.truncate(DateTime.utc_now(), :second)
      )
    else
      changeset
    end
  end

  @doc """
  Remove all blocks matching `ids` that belong to `entry`
  """
  def reject_blocks_belonging_to_entry([], _), do: %{}

  def reject_blocks_belonging_to_entry(ids, entry) do
    schema_and_ids =
      ids
      |> list_root_block_ids_by_source()
      |> list_entry_ids_for_root_blocks_by_source()

    if entry do
      entry_schema = entry.__struct__
      ids_for_schema = Map.get(schema_and_ids, entry_schema) || []
      filtered_ids = Enum.reject(ids_for_schema, &(&1 == entry.id))

      if filtered_ids == [],
        do: Map.delete(schema_and_ids, entry_schema),
        else: Map.put(schema_and_ids, entry_schema, filtered_ids)
    else
      schema_and_ids
    end
  end

  @doc """
  List all registered :blocks fields
  """
  @spec list_blocks :: [module()]
  def list_blocks do
    blueprint_impls = Trait.Blocks.list_implementations()
    Enum.map(blueprint_impls, &{&1, &1.__blocks_fields__()})
  end

  @doc """
  Return block module corresponding to `block_type`
  Used when creating refs in ModuleFormLive
  """
  def get_block_by_type(block_type) do
    default_blocks = Blocks.list_blocks()
    Keyword.get(default_blocks, block_type)
  end

  @doc """
  List all entries with blocks using modules
  """
  def list_module_usage do
    {:ok, module_ids} = Content.list_modules(%{select: [:id], with_deleted: false})

    Enum.map(module_ids, fn %{id: module_id} ->
      module_id
      |> list_block_ids_using_module()
      |> list_root_block_ids_by_source()
      |> list_entry_ids_for_root_blocks_by_source()
    end)
  end

  @doc """
  List all entries with blocks a module is used in
  """
  def list_module_usage(module_id) do
    module_id
    |> list_block_ids_using_module()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
  end

  @doc """
  List all unused modules
  """
  def list_unused_modules do
    query =
      from m in Content.Module,
        left_join: b in Content.Block,
        on: b.module_id == m.id,
        where: is_nil(b.id) and is_nil(m.deleted_at),
        order_by: [asc: m.namespace, asc: m.name],
        select: m

    query
    |> Brando.Repo.all()
    |> Enum.map(&%{name: &1.name, namespace: &1.namespace, id: &1.id})
  end

  @doc """
  List all "orphaned" blocks, i.e. blocks that are not associated with any entry
  """
  def list_orphaned_blocks do
    blocks_query =
      from(b in Brando.Content.Block,
        as: :block,
        select: %{id: b.id, source: b.source},
        where:
          not exists(
            from(j in "pages_blocks",
              select: [:block_id],
              where: j.block_id == parent_as(:block).id
            )
          )
      )

    Brando.Repo.all(blocks_query)
  end

  @doc """
  Render and update all entries with a block using `module_id`
  First syncs the module with the block, renders the block,
  then renders all entries using the block.
  """
  def render_entries_with_module_id(module_id) do
    module_id
    |> list_block_ids_using_module()
    |> sync_and_render_blocks(module_id)
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Render and update all entries with a block using `fragment_id`
  """
  def render_entries_with_fragment_id(fragment_id) do
    fragment_id
    |> list_block_ids_using_fragment()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Render and update all entries with a block using `palette_id`
  """
  def render_entries_with_palette_id(palette_id) do
    palette_id
    |> list_block_ids_using_palette()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Render and update all entries with a block with a var with an identifier
  """
  def render_entries_with_identifier(identifier_id) do
    identifier_id
    |> list_block_ids_using_identifier()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Look through all `villains` for `search_term` and rerender all matching
  """
  def render_entries_matching_regex(search_terms) do
    search_terms
    |> list_block_ids_matching_regex()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Gets all blocks with `module_id` and reapply refs and vars, then saves them.
  Returns a list of all updated block ids.
  """
  def refresh_module_in_blocks(module_id) do
    {:ok, module} =
      Content.get_module(%{
        matches: %{id: module_id},
        preload: [:vars]
      })

    {:ok, blocks} =
      Content.list_blocks(%{
        filter: %{module_id: module_id},
        preload: [:vars]
      })

    Enum.reduce(blocks, [], fn block, acc ->
      updated_changeset = sync_module(block, module)
      Brando.Repo.update(updated_changeset)
      [block.id | acc]
    end)
    |> render_blocks()
  end

  @doc """
  Return list of all blocks using `palette_id`
  """
  def list_block_ids_using_palette(palette_id) do
    query =
      from b in Content.Block,
        select: b.id,
        where: b.palette_id == ^palette_id

    Brando.Repo.all(query)
  end

  @doc """
  Return list of all blocks using `identifier_id`
  """
  def list_block_ids_using_identifier(identifier_id) do
    query =
      from b in Content.Block,
        select: b.id,
        left_join: v in assoc(b, :vars),
        where: v.identifier_id == ^identifier_id

    Brando.Repo.all(query)
  end

  @doc """
  Syncs a block's vars and refs with a module
  """
  def sync_module(block, module) do
    module_refs = module.refs
    module_ref_names = Enum.map(module_refs, & &1.name)
    changeset = Changeset.change(block)
    current_refs = Changeset.get_embed(changeset, :refs, :struct)

    current_refs =
      Enum.filter(current_refs, &(&1.name in module_ref_names))

    current_ref_names = Enum.map(current_refs, & &1.name)
    missing_ref_names = module_ref_names -- current_ref_names

    missing_refs =
      module_refs
      |> Enum.filter(&(&1.name in missing_ref_names))
      |> Brando.Villain.add_uid_to_refs()

    new_refs = current_refs ++ missing_refs

    module_vars = module.vars || []
    module_var_keys = Enum.map(module_vars, & &1.key)

    current_vars = Changeset.get_assoc(changeset, :vars)
    current_var_keys = Enum.map(current_vars, &Changeset.get_field(&1, :key))

    missing_var_keys = module_var_keys -- current_var_keys

    missing_vars =
      module_vars
      |> Enum.filter(&(&1.key in missing_var_keys))
      |> remove_pk_from_vars()
      |> Enum.map(&Changeset.change/1)
      |> Enum.map(&%{&1 | action: :insert})

    new_vars = current_vars ++ missing_vars

    reapplied_refs = reapply_refs(module, module_refs, new_refs)
    reapplied_vars = reapply_vars(module, module_vars, new_vars)

    changeset
    |> Changeset.put_assoc(:vars, reapplied_vars)
    |> Changeset.put_embed(:refs, reapplied_refs)
  end

  def enqueue_entry_map_for_render(entry_map) do
    for {schema, ids} <- entry_map, entry_id <- ids do
      enqueue_entry_for_render(%{schema: schema, entry_id: entry_id})
    end
  end

  def enqueue_entries_for_render(schema, ids) do
    for entry_id <- ids do
      enqueue_entry_for_render(%{schema: schema, entry_id: entry_id})
    end
  end

  def enqueue_entry_for_render(args) do
    args
    |> Brando.Worker.EntryRenderer.new(
      replace_args: true,
      tags: [:render_entry]
    )
    |> Oban.insert()
  end

  defp list_block_ids_using_module(module_id) do
    query =
      from b in Content.Block,
        select: b.id,
        where: b.module_id == ^module_id

    Brando.Repo.all(query)
  end

  defp list_block_ids_using_fragment(fragment_id) do
    query =
      from b in Content.Block,
        select: b.id,
        where: b.fragment_id == ^fragment_id

    Brando.Repo.all(query)
  end

  @doc """
  List ids of `schema` records that has a datasource matching schema OR
  a module containing a datasource matching schema.
  """
  def list_block_ids_using_datamodule(datasource)

  def list_block_ids_using_datamodule({datasource_module, datasource_type, datasource_query}) do
    # find all content modules with this datasource
    {:ok, modules} =
      Brando.Content.list_modules(%{
        filter: %{
          datasource: true,
          datasource_module: to_string(datasource_module),
          datasource_type: to_string(datasource_type),
          datasource_query: to_string(datasource_query)
        },
        select: [:id]
      })

    module_ids = Enum.map(modules, & &1.id)
    list_block_ids_using_modules(module_ids)
  end

  def list_block_ids_using_datamodule(datasource_module) do
    # find all content modules with this datasource
    {:ok, modules} =
      Brando.Content.list_modules(%{
        filter: %{
          datasource: true,
          datasource_module: to_string(datasource_module)
        },
        select: [:id]
      })

    module_ids = Enum.map(modules, & &1.id)

    list_block_ids_using_modules(module_ids)
  end

  def list_entry_ids_for_root_blocks_by_source(source_map) do
    Enum.reduce(source_map, %{}, fn
      {nil, _ids}, acc ->
        acc

      {join_source, ids}, acc ->
        {:assoc, %{queryable: schema}} = Map.get(join_source.__changeset__(), :entry)

        query =
          from js in join_source,
            where: js.block_id in ^ids,
            select: js.entry_id,
            distinct: true

        entry_ids = Brando.Repo.all(query)
        Map.put(acc, schema, entry_ids)
    end)
  end

  def list_block_ids_using_modules(module_ids) when is_list(module_ids) do
    query = from b in Content.Block, where: b.module_id in ^module_ids, select: b.id
    Brando.Repo.all(query)
  end

  def list_root_block_ids_by_source(block_ids) when is_list(block_ids) do
    base_case =
      from(cb in "content_blocks",
        select: %{id: cb.id, parent_id: cb.parent_id, source: cb.source},
        where: cb.id in ^block_ids
      )

    recursive_case =
      from(cb in "content_blocks",
        select: %{id: cb.id, parent_id: cb.parent_id, source: cb.source},
        join: pb in "parent_blocks",
        on: pb.parent_id == cb.id
      )

    query = union_all(base_case, ^recursive_case)

    "parent_blocks"
    |> recursive_ctes(true)
    |> with_cte("parent_blocks", as: ^query)
    |> where([b], is_nil(b.parent_id))
    |> select([b], %{id: b.id, source: b.source})
    |> distinct(true)
    |> Brando.Repo.all()
    |> Enum.reduce(%{}, fn %{id: id, source: source}, acc ->
      {:ok, casted_module} = Brando.Type.Module.cast(source)
      Map.update(acc, casted_module, [id], &(&1 ++ [id]))
    end)
  end

  @doc """
  List all occurences of regex in blocks.
  This should only search refs and vars?
  """
  @spec list_block_ids_matching_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]
  def list_block_ids_matching_regex(search_terms) do
    org_query = from(b in Content.Block, select: %{"id" => b.id})
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    built_query =
      Enum.reduce(search_terms, org_query, fn {search_name, search_term}, query ->
        search_name_refs = to_string(search_name) <> "_refs"
        search_name_vars = to_string(search_name) <> "_vars"

        from(q in query,
          left_join: vars in assoc(q, :vars),
          select_merge: %{
            ^search_name_refs =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(q.refs, :string),
                ^search_term
              ),
            ^search_name_vars =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(vars.value, :string),
                ^search_term
              )
          },
          order_by: [asc: q.id]
        )
      end)

    built_query
    |> Brando.Repo.all()
    |> Enum.map(& &1["id"])
    |> Enum.uniq()
  end

  @doc """
  Searches all modules' `code` for `search_terms`.

  Search terms should be a keyword list with the key being the name of the search and the value being the regex to search for:

  ```
      search_terms = [
        navigation_vars: "{{ navigation\.(.*?) }}",
        navigation_for_loops: "{% for (.*?) in navigation\.(.*?) %}"
      ]

      search_modules_for_regex(search_terms)
  ```
  """
  @spec search_modules_for_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]

  def search_modules_for_regex(search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    org_query =
      from(s in Content.Module,
        select: %{"id" => s.id, "namespace" => s.namespace, "name" => s.name}
      )

    built_query =
      Enum.reduce(search_terms, org_query, fn {search_name, search_term}, query ->
        from(q in query,
          select_merge: %{
            ^to_string(search_name) =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(field(q, :code), :string),
                ^search_term
              )
          }
        )
      end)

    Brando.Repo.all(built_query)
  end

  def sync_and_render_blocks(block_ids, module_id) do
    {:ok, module} =
      Content.get_module(%{
        matches: %{id: module_id},
        preload: [:vars]
      })

    {:ok, blocks} =
      Content.list_blocks(%{
        filter: %{ids: block_ids},
        preload: [:vars]
      })

    blocks
    |> Enum.reduce([], fn block, acc ->
      block
      |> sync_module(module)
      |> Brando.Repo.update()

      [block.id | acc]
    end)
    |> render_blocks()
  end

  def render_blocks(block_ids) do
    # group blocks by the entry they belong to
    source_map = list_root_block_ids_by_source(block_ids)

    for {join_source, ids} <- source_map do
      {:assoc, %{queryable: schema}} = Map.get(join_source.__changeset__(), :entry)

      query =
        from js in join_source,
          where: js.block_id in ^ids,
          select: [js.entry_id, fragment("array_agg(?)", js.block_id)],
          group_by: js.entry_id

      grouped_block_ids = Brando.Repo.all(query)

      for {entry_id, block_ids} <- grouped_block_ids do
        {:ok, entry} = Brando.Query.get_entry(schema, entry_id)

        {:ok, blocks} =
          Brando.Content.list_blocks(%{
            filter: %{ids: block_ids},
            preload: [:vars, :module]
          })

        # render and update all blocks
        for block <- blocks do
          rendered_block = render_block(block, entry)
          # update the block
          changes = %{
            rendered_html: rendered_block,
            rendered_at: DateTime.truncate(DateTime.utc_now(), :second)
          }

          block
          |> Changeset.change(changes)
          |> Brando.Repo.update()
        end
      end
    end

    source_map
  end

  @doc """
  Look through all modules for `search_terms` and rerender all villains that
  use this module
  """
  @spec rerender_matching_modules({atom, binary} | [{atom, binary}]) :: any
  def rerender_matching_modules(search_terms) do
    case search_modules_for_regex(search_terms) |> Enum.map(& &1["id"]) do
      [] -> nil
      ids -> for id <- ids, do: render_entries_with_module_id(id)
    end
  end

  def add_uid_to_refs(nil), do: nil

  def add_uid_to_refs(refs) when is_list(refs) do
    {_, refs_with_generated_uids} =
      get_and_update_in(
        refs,
        [Access.all(), Access.key(:data), Access.key(:uid)],
        &{&1, Brando.Utils.generate_uid()}
      )

    refs_with_generated_uids
  end

  def add_uid_to_refs(changeset) do
    refs = Changeset.get_embed(changeset, :refs)

    updated_refs = Brando.Villain.add_uid_to_ref_changesets(refs)
    Changeset.put_embed(changeset, :refs, updated_refs)
  end

  def add_uid_to_ref_changesets(nil), do: nil

  def add_uid_to_ref_changesets(refs) when is_list(refs) do
    Enum.map(refs, fn ref ->
      data = Changeset.get_field(ref, :data)
      data_changeset = Changeset.change(data)

      updated_data_changeset =
        Changeset.put_change(data_changeset, :uid, Brando.Utils.generate_uid())

      ref
      |> Changeset.put_change(:data, updated_data_changeset)
      |> Map.put(:action, :insert)
    end)
  end

  def remove_pk_from_vars(nil), do: nil
  def remove_pk_from_vars([]), do: []

  def remove_pk_from_vars(vars) when is_list(vars) do
    Enum.map(vars, &Map.merge(&1, %{id: nil, module_id: nil}))
  end

  def reapply_refs(module, module_refs, refs) do
    Enum.map(refs, fn %{name: ref_name, data: %{__struct__: block_module}} = ref ->
      ref_src = Enum.find(module_refs, &(&1.name == ref_name))

      if ref_src == nil do
        raise """

        Ref #{ref_name} not found in module refs!

        Module: ##{module.id} [#{module.namespace}] #{module.name}

        #{inspect(module, pretty: true)}

        """
      end

      ref_src.data.__struct__
      |> block_module.apply_ref(ref_src, ref)
      |> Changeset.change()
    end)
  end

  @protected_and_ignored_var_attrs [
    :value,
    :value_boolean,
    :image_id,
    :palette_id,
    :file_id,
    :identifier_id,
    :page_id,
    :block_id,
    :module_id,
    :global_set_id,
    :menu_item_id,
    :link_text,
    :link_target_blank,
    :link_type,
    # ignored
    :block,
    :id,
    :module,
    :creator,
    :creator_id,
    :file,
    :image,
    :palette,
    :identifier,
    :page,
    :global_set,
    :table_template,
    :table_row,
    :menu_item,
    :__struct__,
    :__meta__
  ]
  def reapply_vars(_module, module_vars, vars) do
    Enum.map(vars, fn
      %Changeset{data: %{key: var_key}} = var ->
        var_src = Enum.find(module_vars, &(&1.key == var_key)) || %{}
        attrs_to_take = Map.keys(var_src) -- @protected_and_ignored_var_attrs
        new_attrs = Map.take(var_src, attrs_to_take)
        Changeset.change(var, new_attrs)
    end)
  end

  def reject_deleted([]), do: []
  def reject_deleted(nil), do: []

  def reject_deleted(block_changesets, root \\ true) when is_list(block_changesets) do
    Enum.reduce(block_changesets, [], fn
      %{action: :delete}, acc ->
        acc

      %{changes: %{mark_as_deleted: true}}, acc ->
        acc

      %{action: :replace}, acc ->
        acc

      block_cs, acc ->
        if root do
          sub_cs = Changeset.get_assoc(block_cs, :block)
          children = Changeset.get_assoc(sub_cs, :children)
          processed_children = reject_deleted(children, false)
          updated_sub_cs = Changeset.put_assoc(sub_cs, :children, processed_children)
          updated_entry_block_cs = Changeset.put_assoc(block_cs, :block, updated_sub_cs)
          [updated_entry_block_cs | acc]
        else
          children = Changeset.get_assoc(block_cs, :children)
          processed_children = reject_deleted(children, false)
          updated_block_cs = Changeset.put_assoc(block_cs, :children, processed_children)
          [updated_block_cs | acc]
        end
    end)
    |> Enum.reverse()
  end

  @doc """
  Returns a list of preloads for a schema if it has the Villain trait
  """
  def preloads_for(schema) do
    if schema.has_trait(Brando.Trait.Blocks) do
      vars_query =
        from v in Brando.Content.Var,
          order_by: [asc: :sequence],
          preload: [:file, :image, :palette, :identifier, :menu_item]

      table_row_query =
        from tr in Brando.Content.TableRow,
          order_by: [asc: :sequence],
          preload: [vars: ^vars_query]

      sub_sub_children_query =
        from b in Brando.Content.Block,
          preload: [
            :palette,
            :container,
            :module,
            :children,
            block_identifiers: :identifier,
            vars: ^vars_query,
            table_rows: ^table_row_query
          ],
          order_by: [asc: :sequence]

      sub_children_query =
        from b in Brando.Content.Block,
          preload: [
            :palette,
            :container,
            :module,
            block_identifiers: :identifier,
            vars: ^vars_query,
            table_rows: ^table_row_query,
            children: ^sub_sub_children_query
          ],
          order_by: [asc: :sequence]

      children_query =
        from b in Brando.Content.Block,
          preload: [
            :palette,
            :container,
            :module,
            vars: ^vars_query,
            table_rows: ^table_row_query,
            block_identifiers: :identifier,
            children: [
              :palette,
              :container,
              :module,
              block_identifiers: :identifier,
              vars: ^vars_query,
              table_rows: ^table_row_query,
              children: ^sub_children_query
            ]
          ],
          order_by: [asc: :sequence]

      Enum.reduce(schema.__blocks_fields__(), [], fn %{name: assoc_name}, acc ->
        field_as_module =
          assoc_name
          |> to_string
          |> Macro.camelize()
          |> String.to_atom()

        join_schema = Module.concat([schema, field_as_module])
        entry_assoc_name = :"entry_#{assoc_name}"

        acc ++
          [
            {entry_assoc_name,
             from(j in join_schema,
               order_by: [asc: :sequence],
               preload: [
                 block: [
                   :parent,
                   :container,
                   :module,
                   :palette,
                   block_identifiers: :identifier,
                   vars: ^vars_query,
                   table_rows: ^table_row_query,
                   children: ^children_query
                 ]
               ]
             )}
          ]
      end)
    else
      []
    end
  end

  alias Ecto.Changeset

  def duplicate_children(changeset, children, current_user_id) do
    duplicated_children =
      Enum.map(children, &duplicate_child(&1, current_user_id))

    Changeset.put_assoc(changeset, :children, duplicated_children)
  end

  def duplicate_child(child_cs, current_user_id) do
    new_uid = Brando.Utils.generate_uid()
    children = child_cs.children
    vars = child_cs.vars
    table_rows = child_cs.table_rows

    child_cs
    |> Map.merge(%{
      id: nil,
      uid: new_uid,
      creator_id: current_user_id,
      parent_id: nil,
      vars: [],
      table_rows: [],
      children: []
    })
    |> Changeset.change()
    |> Map.put(:action, :insert)
    |> duplicate_vars(vars, current_user_id)
    |> duplicate_table_rows(table_rows)
    |> add_uid_to_refs()
    |> Changeset.update_change(:refs, fn ref_changesets ->
      Enum.reject(ref_changesets, &(&1.action == :replace))
    end)
    |> Changeset.update_change(:vars, fn var_changesets ->
      Enum.reject(var_changesets, &(&1.action == :replace))
    end)
    |> duplicate_children(children, current_user_id)
  end

  def duplicate_vars(changeset, %Ecto.Association.NotLoaded{}, _) do
    require Logger

    Logger.error("""

    duplicate_vars ——

    vars NOT LOADED. This should not happen.

    #{inspect(changeset, pretty: true, width: 0)}

    """)

    changeset
  end

  def duplicate_vars(changeset, vars, current_user_id) do
    duplicated_vars = Enum.map(vars, &duplicate_var(&1, current_user_id))
    Changeset.put_assoc(changeset, :vars, duplicated_vars)
  end

  def duplicate_var(var_cs, current_user_id) do
    var_cs
    |> Map.merge(%{id: nil, block_id: nil})
    |> Brando.Content.Var.changeset(%{creator_id: current_user_id})
    |> Map.put(:action, :insert)
  end

  def duplicate_table_rows(changeset, table_rows) do
    duplicated_table_rows = Enum.map(table_rows, &duplicate_table_row/1)
    Changeset.put_assoc(changeset, :table_rows, duplicated_table_rows)
  end

  def duplicate_table_row(table_row_cs) do
    Map.merge(table_row_cs, %{id: nil, block_id: nil})
    |> Brando.Utils.map_from_struct()
  end
end
