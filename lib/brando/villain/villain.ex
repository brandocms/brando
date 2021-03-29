# credo:disable-for-this-file
defmodule Brando.Villain do
  @moduledoc """
  Interface to Villain HTML editor.

  ### Available variables when rendering

    - `{{ entry.<key> }}`
    Gets `<key>` from currently rendering entry. So if we are rendering a `%Page{}` and we
    want the `meta_description` we can do `{{ entry.meta_description }}

    - `{{ links.<key> }}`
    Gets `<key>` from list of links in the Identity configuration.

    - `{{ globals.<category_key>.<key> }}`
    Gets `<key>` from `<category_key>` in list of globals in the Identity configuration.

    - `{{ forloop.index }}`
    Only available inside for loops or modules with `multi` set to true. Returns the current index
    of the for loop, starting at `1`

    - `{{ forloop.index0 }}`
    Only available inside for loops or modules with `multi` set to true. Returns the current index
    of the for loop, starting at `0`

    - `{{ forloop.count }}`
    Only available inside for loops or modules with `multi` set to true. Returns the total amount
    of entries in the for loop

  """
  use Brando.Query

  import Ecto.Query

  alias Brando.Cache
  alias Brando.Pages
  alias Brando.Trait
  alias Brando.Utils
  alias Brando.Villain.Module
  alias Ecto.Changeset
  alias Liquex.Context

  @module_cache_ttl (Brando.config(:env) == :e2e && %{}) || %{cache: {:ttl, :infinite}}

  @doc """
  Parses `json` (in Villain-format).
  Delegates to the parser module configured in the otp_app's brando.exs.
  Renders to HTML.
  """
  @spec parse(binary | [map]) :: binary
  def parse(data, entry \\ nil, opts \\ [])
  def parse("", _, _), do: ""
  def parse(nil, _, _), do: ""

  def parse(json, entry, opts) when is_binary(json),
    do: do_parse(Poison.decode!(json), entry, opts)

  def parse(json, entry, opts) when is_list(json), do: do_parse(json, entry, opts)

  defp do_parse(data, entry, opts) do
    start = System.monotonic_time()
    opts_map = Enum.into(opts, %{})
    parser = Brando.config(Brando.Villain)[:parser]
    {:ok, modules} = list_modules(@module_cache_ttl)

    entry =
      entry
      |> maybe_nil_fields(opts_map)
      |> maybe_put_timestamps()

    context = Context.assign(get_base_context(), "entry", entry)

    opts_map =
      opts_map
      |> Map.put(:context, context)
      |> Map.put(:modules, modules)

    html =
      data
      |> Enum.reduce([], fn data_node, acc ->
        type_atom = String.to_atom(data_node["type"])
        data_node_content = data_node["data"]

        (data_node["hidden"] && ["" | acc]) ||
          [apply(parser, type_atom, [data_node_content, opts_map]) | acc]
      end)
      |> Enum.reverse()
      |> Enum.join()

    output = parse_and_render(html, context)

    :telemetry.execute([:brando, :villain, :parse_and_render], %{
      duration: System.monotonic_time() - start
    })

    output
  end

  # so we don't pass around unneccessary data in the parser
  defp maybe_nil_fields(entry, %{data_field: data_field, html_field: html_field}),
    do: %{entry | data_field => nil, html_field => nil}

  defp maybe_nil_fields(entry, %{data_field: data_field}), do: %{entry | data_field => nil}
  defp maybe_nil_fields(entry, %{html_field: html_field}), do: %{entry | html_field => nil}
  defp maybe_nil_fields(entry, _), do: entry

  def get_base_context() do
    identity = Cache.Identity.get()
    globals = Cache.Globals.get()
    navigation = Cache.Navigation.get()

    %{}
    |> create_context()
    |> add_to_context("identity", identity)
    |> add_to_context("configs", identity.configs)
    |> add_to_context("links", identity.links)
    |> add_to_context("globals", globals)
    |> add_to_context("navigation", navigation)
    |> add_to_context("language", Gettext.get_locale(Brando.gettext()))
  end

  def create_context(vars) do
    Context.new(
      vars,
      filter_module: Brando.Villain.Filters,
      render_module: Brando.Villain.LiquexRenderer
    )
  end

  def add_to_context(context, "configs" = key, value) do
    configs = Enum.map(value, &{String.downcase(&1.key), &1}) |> Enum.into(%{})
    Context.assign(context, key, configs)
  end

  def add_to_context(context, "links" = key, value) do
    links = Enum.map(value, &{String.downcase(&1.name), &1}) |> Enum.into(%{})
    Context.assign(context, key, links)
  end

  def add_to_context(context, "globals" = key, global_categories) do
    parsed_globals =
      Enum.map(global_categories, fn {g_key, g_category} ->
        cat_globs =
          Enum.map(g_category, fn
            {key, %{type: "text", data: %{"value" => value}}} -> {key, value}
            {key, %{type: "html", data: %{"value" => value}}} -> {key, value}
            {key, %{type: "color", data: %{"value" => value}}} -> {key, value}
            {key, %{type: "boolean", data: %{"value" => value}}} -> {key, value}
          end)
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
    {:ok, parsed_doc} = Liquex.parse(html, Brando.Villain.LiquexParser)
    {result, _} = Liquex.Render.render([], parsed_doc, context)
    Enum.join(result)
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
    Enum.map(images, fn image_record ->
      image_struct = image_record.image

      sizes =
        image_struct.sizes
        |> Enum.map(&{elem(&1, 0), Utils.media_url(elem(&1, 1))})
        |> Enum.into(%{})

      %{
        src: Utils.media_url(image_struct.path),
        thumb: image_struct |> Utils.img_url(:thumb) |> Utils.media_url(),
        sizes: sizes,
        dominant_color: image_struct.dominant_color,
        alt: image_struct.alt,
        title: image_struct.title,
        credits: image_struct.credits,
        inserted_at: image_record.inserted_at,
        width: image_struct.width,
        height: image_struct.height,
        webp: image_struct.webp
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
        from s in schema,
          select: s.id
      )

    Enum.map(schema.__villain_fields__(), fn data_field ->
      html_field = get_html_field(schema, data_field)
      rerender_html_from_ids({schema, data_field.name, html_field.name}, ids)
    end)
  end

  @doc """
  Rerender multiple IDS
  """
  @spec rerender_html_from_ids({Module, atom, atom}, [integer | binary]) :: nil | [any()]
  def rerender_html_from_ids(_, []), do: nil
  def rerender_html_from_ids(args, ids), do: for(id <- ids, do: rerender_html_from_id(args, id))

  @doc """
  Rerender HTML from an ID

  ## Example

      rerender_html_from_id({Pages.Page, :data, :html}, 1)

  Will try to rerender html for page with id: 1.

  We treat page fragments special, since they need to propogate to other referencing
  pages and fragments
  """
  @spec rerender_html_from_id(
          {schema :: Module, data_field :: atom, html_field :: atom},
          integer | binary
        ) :: any()
  def rerender_html_from_id({schema, data_field, html_field}, id) do
    query =
      from s in schema,
        where: s.id == ^id

    record = Brando.repo().one(query)
    parsed_data = Brando.Villain.parse(Map.get(record, data_field), record)

    changeset =
      record
      |> Changeset.change()
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

  @doc """
  List all registered Villain fields
  """
  @spec list_villains :: [module()]
  def list_villains do
    Enum.map(Trait.Villain.list_implementations(), &{&1, &1.__villain_fields__()})
  end

  @doc """
  Update all villain fields in database that has a module with `id`.
  """
  def update_module_in_fields(module_id) do
    villains = list_villains()

    result =
      for {schema, fields} <- villains do
        Enum.reduce(fields, [], fn data_field, acc ->
          html_field = get_html_field(schema, data_field)
          ids = list_ids_with_module(schema, data_field.name, module_id)
          [acc | rerender_html_from_ids({schema, data_field.name, html_field.name}, ids)]
        end)
      end

    {:ok, result}
  end

  defp get_html_field(schema, %{name: :data}) do
    schema.__attribute__(:html)
  end

  defp get_html_field(schema, %{name: data_name}) do
    data_name
    |> to_string
    |> String.replace("_data", "_html")
    |> String.to_existing_atom()
    |> schema.__attribute__
  end

  @doc """
  List ids of `schema` records that has `module_id` in `data_field`
  Also check inside containers and datasources
  """
  def list_ids_with_module(schema, data_field, module_id) do
    t = [
      %{type: "module", data: %{id: module_id}}
    ]

    contained_t = [
      %{type: "container", data: %{blocks: [%{type: "module", data: %{id: module_id}}]}}
    ]

    datasourced_t = [
      %{type: "datasource", data: %{module_id: module_id}}
    ]

    Brando.repo().all(
      from s in schema,
        select: s.id,
        where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^t),
        or_where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^contained_t),
        or_where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^datasourced_t)
    )
  end

  @doc """
  Duplicate module
  """
  def duplicate_module(module_id, user) do
    module_id = (is_binary(module_id) && String.to_integer(module_id)) || module_id
    {:ok, module} = get_module(%{matches: %{id: module_id}})

    module =
      module
      |> Map.merge(%{name: "#{module.name} copy", class: "#{module.class} copy"})
      |> Map.delete([:id])
      |> Map.from_struct()

    create_module(module, user)
  end

  mutation :create, Module

  mutation :update, Module do
    fn entry ->
      update_module_in_fields(entry.id)

      {:ok, entry}
    end
  end

  mutation :delete, Module

  @doc """
  Find module with `id` in `modules`
  """
  def find_module(modules, id) do
    modules
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> {:error, {:module, :not_found, id}}
      mod -> {:ok, mod}
    end
  end

  query :list, Module, do: fn query -> from q in query, where: is_nil(q.deleted_at) end

  filters Module do
    fn
      {:name, name}, query ->
        from q in query, where: ilike(q.name, ^"%#{name}%")

      {:namespace, namespace}, query ->
        query =
          from t in query,
            where: is_nil(t.deleted_at),
            order_by: [asc: t.sequence, asc: t.id, desc: t.updated_at]

        namespace =
          (String.contains?(namespace, ",") && String.split(namespace, ",")) || namespace

        case namespace do
          "all" ->
            query

          namespace_list when is_list(namespace_list) ->
            from t in query, where: t.namespace in ^namespace_list

          _ ->
            from t in query, where: t.namespace == ^namespace
        end
    end
  end

  query :single, Module, do: fn query -> from q in query, where: is_nil(q.deleted_at) end

  matches Module do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:name, name}, query ->
        from t in query,
          where: t.name == ^name

      {:namespace, namespace}, query ->
        from t in query,
          where: t.namespace == ^namespace
    end
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
    org_query = from s in schema, select: s.id

    built_query =
      Enum.reduce(search_terms, org_query, fn search_term, query ->
        from q in query,
          or_where: ilike(type(field(q, ^data_field), :string), ^"%#{search_term}%")
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
    org_query = from s in schema, select: %{"id" => s.id}

    built_query =
      Enum.reduce(List.wrap(search_terms), org_query, fn {search_name, search_term}, query ->
        from q in query,
          select_merge: %{
            ^to_string(search_name) =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(field(q, ^data_field), :string),
                ^search_term
              )
          }
      end)

    if with_data,
      do: Brando.repo().all(built_query),
      else: Brando.repo().all(built_query) |> Enum.map(& &1["id"])
  end

  @spec search_modules_for_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]
  def search_modules_for_regex(search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    org_query =
      from s in "pages_modules",
        select: %{"id" => s.id, "namespace" => s.namespace, "name" => s.name}

    built_query =
      Enum.reduce(search_terms, org_query, fn {search_name, search_term}, query ->
        from q in query,
          select_merge: %{
            ^to_string(search_name) =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(field(q, :code), :string),
                ^search_term
              )
          }
      end)

    Brando.repo().all(built_query)
  end

  @doc """
  Look through all `villains` for `search_term` and rerender all matching
  """
  @spec rerender_matching_villains([module], {atom, binary} | [{atom, binary}]) :: [any]
  def rerender_matching_villains(villains, search_terms) do
    for {schema, fields} <- villains do
      Enum.reduce(fields, [], fn data_field, acc ->
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
end
