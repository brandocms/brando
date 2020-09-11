# credo:disable-for-this-file
defmodule Brando.Villain do
  @moduledoc """
  Interface to Villain HTML editor.

  ### Available variables when rendering

    - `${entry:<key>}`
    Gets `<key>` from currently rendering entry. So if we are rendering a `%Page{}` and we
    want the `meta_description` we can do `${entry:meta_description}

    - `${fragment:<parent_key>/<key>/<language>}`
    Gets rendered fragment according to values.

    - `${link:<key>}`
    Gets `<key>` from list of links in the Identity configuration.

    - `${global:<key>}`
    Gets `<key>` from list of globals in the Identity configuration.

    - `${forloop.index}`
    Only available inside for loops or templates with `multi` set to true. Returns the current index
    of the for loop, starting at `1`

    - `${forloop.index0}`
    Only available inside for loops or templates with `multi` set to true. Returns the current index
    of the for loop, starting at `0`

    - `${forloop.count}`
    Only available inside for loops or templates with `multi` set to true. Returns the total amount
    of entries in the for loop

  """
  import Ecto.Query

  alias Brando.Lexer
  alias Brando.Pages
  alias Brando.Utils

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
    parser = Brando.config(Brando.Villain)[:parser]
    identity = Brando.Cache.Identity.get()
    globals = Brando.Cache.Globals.get()

    entry = if opts[:data_field], do: Map.put(entry, opts[:data_field], nil), else: entry
    entry = if opts[:html_field], do: Map.put(entry, opts[:html_field], nil), else: entry
    entry = maybe_put_timestamps(entry)

    context =
      %{}
      |> Lexer.Context.new()
      |> Lexer.Context.assign("entry", entry)
      |> Lexer.Context.assign("globals", globals)
      |> Lexer.Context.assign("identity", identity)
      |> Lexer.Context.assign("configs", identity.configs)
      |> Lexer.Context.assign("links", identity.links)

    opts = Keyword.put(opts, :context, context)

    html =
      data
      |> Enum.reduce([], fn data_node, acc ->
        type_atom = String.to_atom(data_node["type"])
        data_node_content = data_node["data"]
        [apply(parser, type_atom, [data_node_content, opts]) | acc]
      end)
      |> Enum.reverse()
      |> Enum.join()

    Lexer.parse_and_render(html, context)
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
        %Ecto.Changeset{} = changeset,
        field \\ nil
      ) do
    data_field = (field && field |> to_string |> Kernel.<>("_data") |> String.to_atom()) || :data
    html_field = (field && field |> to_string |> Kernel.<>("_html") |> String.to_atom()) || :html

    applied_changes = Ecto.Changeset.apply_changes(changeset)
    data_src = Map.get(applied_changes, data_field)

    parsed_data =
      Brando.Villain.parse(data_src, applied_changes,
        data_field: data_field,
        html_field: html_field
      )

    changeset
    |> Ecto.Changeset.put_change(html_field, parsed_data)
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
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(
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
  Get template from DB
  """
  def get_template(id) do
    query =
      from t in Brando.Villain.Template,
        where: t.id == ^id and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:template, :not_found}}
      t -> {:ok, t}
    end
  end

  @doc """
  Get template from CACHE or DB
  """
  def get_cached_template(id) do
    case Cachex.get(:cache, "template__#{id}") do
      {:ok, nil} ->
        {:ok, template} = get_template(id)
        Cachex.put(:cache, "template__#{id}", template, ttl: :timer.seconds(120))
        {:ok, template}

      {:ok, template} ->
        {:ok, template}
    end
  end

  @doc """
  Update or create template in DB
  """
  def update_or_create_template(%{"data" => %{"id" => id} = data}) do
    with {:ok, template} <- get_template(id) do
      params = Map.drop(data, ["id"])

      {:ok, new_template} =
        template
        |> Brando.Villain.Template.changeset(params)
        |> Brando.repo().update

      update_template_in_fields(id)

      {:ok, new_template}
    end
  end

  def update_or_create_template(%{"data" => params}) do
    %Brando.Villain.Template{}
    |> Brando.Villain.Template.changeset(params)
    |> Brando.repo().insert
  end

  @doc """
  Delete template by `id`
  """
  def delete_template(id) do
    {:ok, template} = get_template(id)
    Brando.repo().delete(template)
  end

  @doc """
  List templates by namespace
  """
  def list_templates(namespace) do
    query =
      from t in Brando.Villain.Template,
        where: is_nil(t.deleted_at),
        order_by: [asc: t.sequence, asc: t.id, desc: t.updated_at]

    namespace = (String.contains?(namespace, ",") && String.split(namespace, ",")) || namespace

    query =
      case namespace do
        "all" ->
          query

        namespace_list when is_list(namespace_list) ->
          from t in query, where: t.namespace in ^namespace_list

        _ ->
          from t in query, where: t.namespace == ^namespace
      end

    {:ok, Brando.repo().all(query)}
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
          search_terms :: binary | [binary]
        ) :: [any]
  def search_villains_for_regex(schema, data_field, search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]
    org_query = from s in schema, select: s.id

    built_query =
      Enum.reduce(search_terms, org_query, fn search_term, query ->
        from q in query,
          or_where: fragment("? ~* ?", type(field(q, ^data_field), :string), ^"#{search_term}")
      end)

    Brando.repo().all(built_query)
  end

  @doc """
  Look through all `villains` for `search_term` and rerender all matching
  """
  @spec rerender_matching_villains([any], binary | [binary]) :: [any]
  def rerender_matching_villains(villains, search_terms) do
    for {schema, fields} <- villains do
      Enum.reduce(fields, [], fn {_, data_field, html_field}, acc ->
        case search_villains_for_text(schema, data_field, search_terms) do
          [] ->
            acc

          ids ->
            [rerender_html_from_ids({schema, data_field, html_field}, ids) | acc]
        end
      end)
    end
  end

  @doc """
  Look through all templates for `search_terms` and rerender all villains that
  use this template
  """
  @spec rerender_matching_villains([any], binary | [binary]) :: any
  def rerender_matching_templates(_villains, search_terms) do
    # first look through templates
    query = from(t in Brando.Villain.Template, select: t.id)

    built_query =
      Enum.reduce(search_terms, query, fn search_term, query ->
        from q in query,
          or_where: ilike(type(q.code, :string), ^"%#{search_term}%")
      end)

    case Brando.repo().all(built_query) do
      [] ->
        nil

      ids ->
        for id <- ids do
          update_template_in_fields(id)
        end
    end
  end
end
