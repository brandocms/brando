# credo:disable-for-this-file
defmodule Brando.Villain do
  use Brando.Query

  import Ecto.Query
  import Brando.Query.Helpers

  alias Brando.Cache
  alias Brando.Content
  alias Brando.Content.Module
  alias Brando.Pages
  alias Brando.Trait
  alias Brando.Utils
  alias Brando.Villain.Blocks
  alias Ecto.Changeset
  alias Liquex.Context

  @type changeset :: Ecto.Changeset.t()

  @module_cache_ttl (Brando.config(:env) == :e2e && %{preload: [:vars]}) ||
                      %{cache: {:ttl, :infinite}, preload: [:vars]}
  @palette_cache_ttl (Brando.config(:env) == :e2e && %{}) || %{cache: {:ttl, :infinite}}
  @fragment_cache_ttl (Brando.config(:env) == :e2e && %{}) || %{cache: {:ttl, :infinite}}

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
    require Logger

    Logger.error("""
    => parse
    sequence —> block_id
    """)

    Enum.each(entry_blocks_list, fn entry_block ->
      Logger.error("#{inspect(entry_block.sequence)} — #{inspect(entry_block.block_id)}")
    end)

    start = System.monotonic_time()
    opts_map = Enum.into(opts, %{})
    parser = Brando.config(Brando.Villain)[:parser]

    {:ok, modules} = Content.list_modules(@module_cache_ttl)
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
      |> Map.put(:palettes, palettes)
      |> Map.put(:fragments, fragments)

    html =
      entry_blocks_list
      |> Enum.reduce([], fn
        %{block: %{active: false}}, acc -> acc
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
    do_get_base_context(to_string(entry_language))
    |> add_to_context("language", to_string(entry_language))
    |> add_to_context("locale", to_string(entry_language))
    |> add_to_context("entry", entry)
  end

  def get_base_context(entry) do
    locale = Gettext.get_locale(Brando.gettext())

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
    with {:ok, parsed_doc} <- Liquex.parse(html, Brando.Villain.LiquexParser),
         {result, _} <- Liquex.Render.render!([], parsed_doc, context) do
      Enum.join(result)
    else
      {:error, "expected end of string", err} ->
        require Logger
        Logger.error("==> Error parsing liquex template")
        Logger.error(inspect(err, pretty: true))
        ">>> Error parsing liquex template <<<"
    end
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
  Rerender page HTML from data.
  """
  def rerender_html(
        %Changeset{} = changeset,
        field \\ nil
      ) do
    data_field = (field && field |> to_string |> Kernel.<>("_data") |> String.to_atom()) || :data
    html_field = (field && field |> to_string |> Kernel.<>("_html") |> String.to_atom()) || :html

    applied_changes = Changeset.apply_changes(changeset)
    data_src = Map.get(applied_changes, data_field)

    parsed_data =
      Brando.Villain.parse(data_src, applied_changes,
        data_field: data_field,
        html_field: html_field
      )

    changeset
    |> Changeset.put_change(html_field, parsed_data)
    |> Brando.repo().update!
  end

  @doc """
  Rerenders HTML for all ids in `schema`

  ### Example

      iex> rerender_villains_for(Brando.Pages.Page)

  """
  def rerender_villains_for(schema) do
    ids =
      Brando.repo().all(
        from(s in schema,
          select: s.id
        )
      )

    Enum.map(schema.__villain_fields__(), fn
      {:villain, data_field, html_field} ->
        rerender_html_from_ids({schema, data_field, html_field}, ids)

      data_field ->
        html_field = get_html_field(schema, data_field)
        rerender_html_from_ids({schema, data_field.name, html_field.name}, ids)
    end)
  end

  @doc """
  Rerender blocks for id/schema

  ## Example

      rerender_blocks(Pages.Page, 1)

  Will try to rerender all block fields for page with id: 1.

  We treat page fragments special, since they need to propagate to other referencing
  pages and fragments
  """
  @spec rerender_blocks(schema :: module, id :: integer | binary) ::
          {:ok, map} | {:error, changeset}
  def rerender_blocks(schema, id, updated_module_id \\ nil) do
    # ctx = schema.__modules__().context
    # singular = schema.__naming__().singular

    # get_opts =
    #   if schema.has_trait(Brando.Trait.SoftDelete) do
    #     %{matches: %{id: id}, with_deleted: true}
    #   else
    #     %{matches: %{id: id}}
    #   end

    # case apply(ctx, :"get_#{singular}", [get_opts]) do
    #   {:error, _} = err ->
    #     require Logger

    #     Logger.error("""
    #     ==> Failed to rerender_html_from_id

    #     #{inspect(err, pretty: true)}

    #     Schema..: #{inspect(schema, pretty: true)}
    #     Id......: #{inspect(id, pretty: true)}

    #     """)

    #   {:ok, record} ->
    #     {:ok, modules} = Content.list_modules(@module_cache_ttl)

    #     data = Map.get(record, data_field)

    #     updated_data =
    #       if updated_module_id do
    #         module = Enum.find(modules, &(&1.id == updated_module_id))
    #         Brando.Villain.reapply_module(module, data)
    #       else
    #         data
    #       end

    #     parsed_data = Brando.Villain.parse(updated_data, record)

    #     changeset =
    #       record
    #       |> Changeset.change()
    #       |> Changeset.put_change(
    #         data_field,
    #         updated_data
    #       )
    #       |> Changeset.put_change(
    #         html_field,
    #         parsed_data
    #       )

    #     case Brando.repo().update(changeset) do
    #       {:ok, %Pages.Fragment{} = fragment} ->
    #         Brando.Cache.Query.evict({:ok, fragment})
    #         Pages.update_villains_referencing_fragment(fragment)

    #       {:ok, result} ->
    #         Brando.Cache.Query.evict({:ok, result})

    #         {:ok, result}
    #     end
    # end
  end

  @doc """
  Rerender multiple IDS
  """
  @spec rerender_html_from_ids({Module, atom, atom}, [integer | binary]) :: nil | [any()]
  def rerender_html_from_ids(_, []), do: nil

  def rerender_html_from_ids(args, ids, updated_module_id \\ nil),
    do: for(id <- ids, do: rerender_html_from_id(args, id, updated_module_id))

  @doc """
  Rerender HTML from an ID

  ## Example

      rerender_html_from_id({Pages.Page, :data, :html}, 1)

  Will try to rerender html for page with id: 1.

  We treat page fragments special, since they need to propagate to other referencing
  pages and fragments
  """
  # TODO: DEPRECATE AND DELETE
  @spec rerender_html_from_id(
          {schema :: module, data_field :: atom, html_field :: atom},
          integer | binary
        ) :: {:ok, map} | {:error, changeset}
  def rerender_html_from_id({schema, data_field, html_field}, id, updated_module_id \\ nil) do
    ctx = schema.__modules__().context
    singular = schema.__naming__().singular

    get_opts =
      if schema.has_trait(Brando.Trait.SoftDelete) do
        %{matches: %{id: id}, with_deleted: true}
      else
        %{matches: %{id: id}}
      end

    case apply(ctx, :"get_#{singular}", [get_opts]) do
      {:error, _} = err ->
        require Logger

        Logger.error("""
        ==> Failed to rerender_html_from_id

        #{inspect(err, pretty: true)}

        Schema..: #{inspect(schema, pretty: true)}
        Id......: #{inspect(id, pretty: true)}

        """)

      {:ok, record} ->
        {:ok, modules} = Content.list_modules(@module_cache_ttl)

        data = Map.get(record, data_field)

        updated_data =
          if updated_module_id do
            module = Enum.find(modules, &(&1.id == updated_module_id))
            Brando.Villain.reapply_module(module, data)
          else
            data
          end

        parsed_data = Brando.Villain.parse(updated_data, record)

        changeset =
          record
          |> Changeset.change()
          |> Changeset.put_change(
            data_field,
            updated_data
          )
          |> Changeset.put_change(
            html_field,
            parsed_data
          )

        case Brando.repo().update(changeset) do
          {:ok, %Pages.Fragment{} = fragment} ->
            Brando.Cache.Query.evict({:ok, fragment})
            Pages.update_villains_referencing_fragment(fragment)

          {:ok, result} ->
            Brando.Cache.Query.evict({:ok, result})

            {:ok, result}
        end
    end
  end

  @doc """
  List all registered Villain fields
  """
  @spec list_villains :: [module()]
  def list_villains do
    blueprint_impls = Trait.Villain.list_implementations()
    Enum.map(blueprint_impls, &{&1, &1.__villain_fields__()})
  end

  @doc """
  Return block module corresponding to `block_type`
  Used when creating refs in ModuleUpdateLive
  """
  def get_block_by_type(block_type) do
    default_blocks = Blocks.list_blocks()
    Keyword.get(default_blocks, block_type)
  end

  def update_palette_in_fields(palette_id) do
    villains = list_villains()

    result =
      for {schema, fields} <- villains do
        Enum.reduce(fields, [], fn
          data_field, acc ->
            html_field = get_html_field(schema, data_field)

            case list_ids_with_palette(schema, data_field.name, palette_id) do
              [] ->
                acc

              ids ->
                [acc | rerender_html_from_ids({schema, data_field.name, html_field.name}, ids)]
            end
        end)
      end

    {:ok, result}
  end

  @doc """
  List all {schema, data_field_name, ids} a module is used in
  """
  def list_module_usage(module_id) do
    villains = list_villains()

    result =
      for {schema, fields} <- villains do
        Enum.reduce(fields, [], fn
          data_field, acc ->
            ids = list_ids_with_modules(schema, data_field.name, [module_id])

            if ids == [] do
              acc
            else
              [{schema, data_field.name, ids} | acc]
            end
        end)
      end

    {:ok, Enum.filter(result, &(&1 != []))}
  end

  @doc """
  List all unused modules
  """
  def list_unused_modules do
    villains = list_villains()

    for module <- Content.list_modules!(%{select: [:id, :name, :namespace], order: "asc id"}) do
      reduced_fors =
        for {schema, fields} <- villains do
          reduced_fields =
            Enum.reduce(fields, [], fn
              data_field, acc ->
                ids = list_ids_with_modules(schema, data_field.name, [module.id])

                if ids == [] do
                  [:unused | acc]
                else
                  [:in_use | acc]
                end
            end)

          if Enum.any?(reduced_fields, &(&1 == :in_use)) do
            :in_use
          else
            :unused
          end
        end

      (Enum.any?(reduced_fors, &(&1 == :in_use)) && :in_use) ||
        {:module, module.id, module.name, :unused}
    end
    |> Enum.reject(&(&1 == :in_use))
  end

  @doc """
  Update all villain fields in database that has a module with `id`.
  """
  def update_module_in_fields(module_id) do
    module_id
    |> list_block_ids_using_module_id()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  defp enqueue_entry_map_for_render(entry_map) do
    for {schema, ids} <- entry_map do
      Brando.Villain.enqueue_entry_map_for_render(schema, ids)
    end
  end

  defp list_block_ids_using_module_id(module_id) do
    query =
      from b in Content.Block,
        select: b.id,
        where: b.module_id == ^module_id

    Brando.repo().all(query)
  end

  defp list_entry_ids_for_root_blocks_by_source(source_map) do
    Enum.reduce(source_map, %{}, fn {join_source, ids}, acc ->
      {:assoc, %{queryable: schema}} = Map.get(join_source.__changeset__(), :entry)

      query =
        from js in join_source,
          where: js.block_id in ^ids,
          select: js.entry_id,
          distinct: true

      entry_ids = Brando.repo().all(query)
      Map.put(acc, schema, entry_ids)
    end)
  end

  defp rerender_entries_with_module_ids(blocks) do
    block_ids = Enum.map(blocks, & &1.id)

    for {schema, ids} <- list_root_block_ids_by_source(block_ids) do
    end
  end

  defp list_root_block_ids_by_source(block_ids) do
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
    |> Brando.repo().all()
    |> Enum.reduce(%{}, fn %{id: id, source: source}, acc ->
      {:ok, casted_module} = Brando.Type.Module.cast(source)
      Map.update(acc, casted_module, [id], &(&1 ++ [id]))
    end)
  end

  @doc """
  Update all villain fields in database that has a fragment with `id`.
  """
  def update_fragment_in_fields(fragment_id) do
    villains = list_villains()

    result =
      for {schema, fields} <- villains do
        Enum.reduce(fields, [], fn
          {:villain, data_field, html_field}, acc ->
            ids = list_ids_with_fragments(schema, data_field, [fragment_id])
            [acc | rerender_html_from_ids({schema, data_field, html_field}, ids, fragment_id)]

          data_field, acc ->
            html_field = get_html_field(schema, data_field)

            case list_ids_with_fragments(schema, data_field.name, [fragment_id]) do
              [] ->
                acc

              ids ->
                [
                  acc
                  | rerender_html_from_ids(
                      {schema, data_field.name, html_field.name},
                      ids,
                      fragment_id
                    )
                ]
            end
        end)
      end

    {:ok, result}
  end

  def get_html_field(schema, %{name: :data}) do
    schema.__attribute__(:html)
  end

  def get_html_field(schema, %{name: data_name}) do
    data_name
    |> to_string
    |> String.replace("_data", "_html")
    |> String.to_existing_atom()
    |> schema.__attribute__
  end

  @doc """
  List ids of `schema` records that has a container block with
  `palette_id` in `data_field`.
  """
  def list_ids_with_palette(schema, data_field, palette_id) do
    t = [
      %{type: "container", data: %{palette_id: palette_id}}
    ]

    Brando.repo().all(
      from(s in schema,
        select: s.id,
        where: jsonb_contains(s, data_field, t)
      )
    )
  end

  @doc """
  List ids of `schema` records that has `module_ids` in `data_field`
  Also check inside containers.
  """
  def list_ids_with_modules(schema, data_field, module_ids) when is_list(module_ids) do
    query =
      from s in schema,
        select: s.id

    query =
      Enum.reduce(module_ids, query, fn module_id, updated_query ->
        t = [
          %{type: "module", data: %{module_id: module_id}}
        ]

        contained_t = [
          %{
            type: "container",
            data: %{blocks: [%{type: "module", data: %{module_id: module_id}}]}
          }
        ]

        from s in updated_query,
          or_where: jsonb_contains(s, data_field, t),
          or_where: jsonb_contains(s, data_field, contained_t)
      end)

    Brando.repo().all(query)
  end

  @doc """
  List ids of `schema` records that has `fragment_ids` in `data_field`
  Also check inside containers.
  """
  def list_ids_with_fragments(schema, data_field, fragment_ids) when is_list(fragment_ids) do
    query =
      from s in schema,
        select: s.id

    query =
      Enum.reduce(fragment_ids, query, fn fragment_id, updated_query ->
        t = [
          %{type: "fragment", data: %{fragment_id: fragment_id}}
        ]

        contained_t = [
          %{
            type: "container",
            data: %{blocks: [%{type: "fragment", data: %{fragment_id: fragment_id}}]}
          }
        ]

        from s in updated_query,
          or_where: jsonb_contains(s, data_field, t),
          or_where: jsonb_contains(s, data_field, contained_t)
      end)

    Brando.repo().all(query)
  end

  @doc """
  List all occurences of fragment in `schema`'s `data_field`
  """
  @spec search_villains_for_text(
          schema :: any,
          data_field :: atom,
          search_terms :: binary | [binary]
        ) :: [any]
  def search_villains_for_text(schema, data_field, search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]
    org_query = from(s in schema, select: s.id, order_by: [asc: s.id])

    built_query =
      Enum.reduce(search_terms, org_query, fn search_term, query ->
        from(q in query,
          or_where: ilike(type(field(q, ^data_field), :string), ^"%#{search_term}%")
        )
      end)

    Brando.repo().all(built_query)
  end

  @doc """
  List all occurences of regex in `schema`'s `data_field`
  """
  @spec search_villains_for_regex(
          schema :: any,
          data_field :: atom,
          search_terms :: {atom, binary} | [{atom, binary}]
        ) :: [any]
  def search_villains_for_regex(schema, data_field, search_terms, with_data \\ nil) do
    org_query = from(s in schema, select: %{"id" => s.id})

    built_query =
      Enum.reduce(List.wrap(search_terms), org_query, fn {search_name, search_term}, query ->
        from(q in query,
          select_merge: %{
            ^to_string(search_name) =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(field(q, ^data_field), :string),
                ^search_term
              )
          },
          order_by: [asc: q.id]
        )
      end)

    if with_data,
      do: Brando.repo().all(built_query),
      else: Brando.repo().all(built_query) |> Enum.map(& &1["id"])
  end

  @spec search_modules_for_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]
  def search_modules_for_regex(search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    org_query =
      from(s in Module,
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

    Brando.repo().all(built_query)
  end

  @doc """
  Look through all `villains` for `search_term` and rerender all matching
  """
  @spec rerender_matching_villains([module], {atom, binary} | [{atom, binary}]) :: [any]
  def rerender_matching_villains(villains, search_terms) do
    for {schema, fields} <- villains do
      Enum.reduce(fields, [], fn
        {:villain, data_field, html_field}, acc ->
          case search_villains_for_regex(schema, data_field, search_terms) do
            [] ->
              acc

            ids ->
              [rerender_html_from_ids({schema, data_field, html_field}, ids) | acc]
          end

        data_field, acc ->
          html_field = get_html_field(schema, data_field)

          case search_villains_for_regex(schema, data_field.name, search_terms) do
            [] ->
              acc

            ids ->
              [rerender_html_from_ids({schema, data_field.name, html_field.name}, ids) | acc]
          end
      end)
    end
  end

  @doc """
  Look through all modules for `search_terms` and rerender all villains that
  use this module
  """
  @spec rerender_matching_modules([module], {atom, binary} | [{atom, binary}]) :: any
  def rerender_matching_modules(_villains, search_terms) do
    case search_modules_for_regex(search_terms) |> Enum.map(& &1["id"]) do
      [] -> nil
      ids -> for id <- ids, do: update_module_in_fields(id)
    end
  end

  @doc """
  Recursively search a list of blocks for block matching `uid`
  """
  @spec find_block(list(), binary()) :: map | nil
  def find_block(blocks, uid, acc \\ nil)
  def find_block(_, nil, _), do: nil
  def find_block(nil, _, acc), do: acc

  def find_block(blocks, uid, acc) do
    Enum.reduce_while(blocks, acc, fn
      %{uid: ^uid} = block, _ ->
        {:halt, block}

      %{type: "container", data: %{blocks: blocks}}, _ ->
        ret = find_block(blocks, uid, acc)

        if ret do
          {:halt, ret}
        else
          {:cont, acc}
        end

      %{type: "module", data: %{refs: refs}}, _ ->
        ret = find_block(refs, uid, acc)

        if ret do
          {:halt, ret}
        else
          {:cont, acc}
        end

      %Content.Module.Ref{data: %{uid: ^uid} = block}, _ ->
        {:halt, block}

      _, acc ->
        {:cont, acc}
    end) || acc
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

  def add_uid_to_ref_changesets(nil), do: nil

  def add_uid_to_ref_changesets(refs) when is_list(refs) do
    Enum.map(refs, fn ref ->
      data = Changeset.get_field(ref, :data)
      data_changeset = Changeset.change(data)

      updated_data_changeset =
        Changeset.put_change(data_changeset, :uid, Brando.Utils.generate_uid())

      Changeset.put_change(ref, :data, updated_data_changeset)
      |> Map.put(:action, :insert)
    end)
  end

  def remove_pk_from_vars(nil), do: nil
  def remove_pk_from_vars([]), do: []

  def remove_pk_from_vars(vars) when is_list(vars) do
    Enum.map(vars, fn var ->
      Map.merge(var, %{id: nil, module_id: nil})
    end)
  end

  def reapply_module(%{id: module_id} = module, data) do
    Enum.reduce(data, [], fn
      %{type: "module", data: %{module_id: ^module_id}} = module_block, acc ->
        reapplied_data = reapply_module_data(module, module_block.data)
        [Map.put(module_block, :data, reapplied_data) | acc]

      %{type: "module"} = module_block, acc ->
        [module_block | acc]

      %{type: "container", data: %{blocks: blocks}} = container, acc ->
        [
          put_in(
            container,
            [
              Access.key(:data),
              Access.key(:blocks)
            ],
            reapply_module(module, blocks)
          )
          | acc
        ]

      block, acc ->
        [block | acc]
    end)
    |> Enum.reverse()
  end

  def reapply_module_data(module, original_block) do
    module_refs = module.refs || []
    module_ref_names = Enum.map(module_refs, & &1.name)

    # drop old refs
    current_refs = Enum.filter(original_block.refs, &(&1.name in module_ref_names)) || []
    current_ref_names = Enum.map(current_refs, & &1.name)

    # find missing refs
    missing_ref_names = module_ref_names -- current_ref_names
    missing_refs = Enum.filter(module_refs, &(&1.name in missing_ref_names))

    new_refs = current_refs ++ missing_refs

    # find missing vars
    current_vars = original_block.vars || []
    current_var_keys = Enum.map(current_vars, & &1.key)

    module_vars = module.vars || []
    module_var_keys = Enum.map(module_vars, & &1.key)

    missing_var_keys = module_var_keys -- current_var_keys
    missing_vars = Enum.filter(module_vars, &(&1.key in missing_var_keys))

    new_vars = current_vars ++ missing_vars

    reapplied_refs = reapply_refs(module, module_refs, new_refs)
    reapplied_vars = reapply_vars(module, module_vars, new_vars)

    original_block
    |> put_in([Access.key(:refs)], reapplied_refs)
    |> put_in([Access.key(:vars)], reapplied_vars)
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

      block_module.apply_ref(ref_src.data.__struct__, ref_src, ref)
    end)
  end

  def reapply_vars(_module, module_vars, vars) do
    Enum.map(vars, fn %{key: var_key, __struct__: _var_module} = var ->
      var_src = Enum.find(module_vars, &(&1.key == var_key)) || %{}

      protected_attrs = [
        :value,
        :value_boolean,
        :image_id,
        :palette_id,
        :file_id,
        :linked_identifier_id,
        :page_id,
        :block_id,
        :module_id,
        :global_set_id
      ]

      overwritten_attrs = Map.keys(var_src) -- protected_attrs
      new_attrs = Map.take(var_src, overwritten_attrs)
      Map.merge(var, new_attrs)
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
end
