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
    Only available inside for loops or templates with `multi` set to true. Returns the current index
    of the for loop, starting at `1`

    - `{{ forloop.index0 }}`
    Only available inside for loops or templates with `multi` set to true. Returns the current index
    of the for loop, starting at `0`

    - `{{ forloop.count }}`
    Only available inside for loops or templates with `multi` set to true. Returns the total amount
    of entries in the for loop

  """
  use Brando.Query

  import Ecto.Query

  alias Brando.Cache
  alias Brando.Pages
  alias Brando.Utils
  alias Brando.Villain.Template
  alias Ecto.Changeset
  alias Liquex.Context

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

    entry =
      entry
      |> maybe_nil_fields(opts_map)
      |> maybe_put_timestamps()

    context = Context.assign(get_base_context(), "entry", entry)
    opts_map = Map.put(opts_map, :context, context)

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
        title: image_struct.title,
        credits: image_struct.credits,
        inserted_at: image_record.inserted_at,
        width: image_struct.width,
        height: image_struct.height
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

    {_, villain_fields} = schema.__villain_fields__()

    Enum.map(villain_fields, fn {:villain, data_field, html_field} ->
      rerender_html_from_ids({schema, data_field, html_field}, ids)
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
      {:ok, %Pages.PageFragment{} = page_fragment} ->
        Pages.update_villains_referencing_fragment(page_fragment)

      {:ok, result} ->
        {:ok, result}
    end
  end

  @doc """
  List all registered Villain fields
  """
  @spec list_villains :: [module()]
  def list_villains do
    {:ok, app_modules} = :application.get_key(Brando.otp_app(), :modules)

    modules = (app_modules ++ [Pages.Page, Pages.PageFragment]) |> Enum.uniq()

    modules
    |> Enum.filter(&({:__villain_fields__, 0} in &1.__info__(:functions)))
    |> Enum.map(& &1.__villain_fields__())
  end

  @doc """
  Update all villain fields in database that has a template with `id`.
  """
  def update_template_in_fields(template_id) do
    villains = list_villains()

    result =
      for {schema, fields} <- villains do
        Enum.reduce(fields, [], fn {_, data_field, html_field}, acc ->
          ids = list_ids_with_template(schema, data_field, template_id)
          [acc | rerender_html_from_ids({schema, data_field, html_field}, ids)]
        end)
      end

    {:ok, result}
  end

  @doc """
  List ids of `schema` records that has `template_id` in `data_field`
  """
  def list_ids_with_template(schema, data_field, template_id) do
    t = [%{type: "template", data: %{id: template_id}}]
    d = [%{type: "datasource", data: %{template: template_id}}]

    Brando.repo().all(
      from s in schema,
        select: s.id,
        where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^t),
        or_where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^d)
    )
  end

  @doc """
  Get template from CACHE or DB
  """
  def get_cached_template(id) do
    case Cachex.get(:cache, "template__#{id}") do
      {:ok, nil} ->
        {:ok, template} = get_template(%{matches: %{id: id}})
        Cachex.put(:cache, "template__#{id}", template, ttl: :timer.seconds(120))
        {:ok, template}

      {:ok, template} ->
        {:ok, template}
    end
  end

  @doc """
  Duplicate template
  """
  def duplicate_template(template_id) do
    template_id = (is_binary(template_id) && String.to_integer(template_id)) || template_id
    {:ok, template} = get_template(%{matches: %{id: template_id}})

    template =
      template
      |> Map.merge(%{name: "#{template.name} copy", class: "#{template.class} copy"})
      |> Map.delete([:id])
      |> Map.from_struct()

    create_template(template)
  end

  @doc """
  Update or create template in DB
  """
  def update_template(id, params) do
    with {:ok, template} <- get_template(%{matches: %{id: id}}) do
      {:ok, new_template} =
        template
        |> Template.changeset(params)
        |> Brando.repo().update

      update_template_in_fields(id)

      {:ok, new_template}
    end
  end

  def create_template(params) do
    %Template{}
    |> Template.changeset(params)
    |> Brando.repo().insert
  end

  @doc """
  Delete template by `id`
  """
  def delete_template(id) do
    {:ok, template} = get_template(%{matches: %{id: id}})

    Brando.repo().delete(template)
  end

  query :list, Template do
    fn query -> from q in query, where: is_nil(q.deleted_at) end
  end

  filters Template do
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

  query :single, Template, do: fn query -> from q in query, where: is_nil(q.deleted_at) end

  matches Template do
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
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]
    org_query = from s in schema, select: %{"id" => s.id}

    built_query =
      Enum.reduce(search_terms, org_query, fn {search_name, search_term}, query ->
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

  @spec search_templates_for_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]
  def search_templates_for_regex(search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    org_query =
      from s in "pages_templates",
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
      Enum.reduce(fields, [], fn {_, data_field, html_field}, acc ->
        case search_villains_for_regex(schema, data_field, search_terms) do
          [] -> acc
          ids -> [rerender_html_from_ids({schema, data_field, html_field}, ids) | acc]
        end
      end)
    end
  end

  @doc """
  Look through all templates for `search_terms` and rerender all villains that
  use this template
  """
  @spec rerender_matching_templates([module], {atom, binary} | [{atom, binary}]) :: any
  def rerender_matching_templates(_villains, search_terms) do
    case search_templates_for_regex(search_terms) |> Enum.map(& &1["id"]) do
      [] -> nil
      ids -> for id <- ids, do: update_template_in_fields(id)
    end
  end
end
