# credo:disable-for-this-file
defmodule Brando.Villain do
  @moduledoc """
  Interface to Villain HTML editor.
  """

  alias Brando.Pages
  alias Brando.Utils
  import Ecto.Query

  @regex_fragment_ref ~r/(?:\$\{|\$\%7B)FRAGMENT:([a-zA-Z0-9-_]+)\/([a-zA-Z0-9-_]+)\/(\w+)(?:\}|\%7D)/
  @regex_config_ref ~r/(?:\$\{|\$\%7B)CONFIG:([a-zA-Z0-9-_]+)(?:\}|\%7D)/
  @regex_link_ref ~r/(?:\$\{|\$\%7B)LINK:([a-zA-Z0-9-_]+)(?:\}|\%7D)/
  @regex_global_ref ~r/(?:\$\{|\$\%7B)GLOBAL:([a-zA-Z0-9-_]+)(?:\}|\%7D)/
  @regex_identity_ref ~r/(?:\$\{|\$\%7B)IDENTITY:([a-zA-Z0-9-_]+)(?:\}|\%7D)/

  defmacro __using__(:schema) do
    raise "`use Brando.Villain, :schema` is deprecated. Call `use Brando.Villain.Schema` instead."
  end

  defmacro __using__(:migration) do
    raise "`use Brando.Villain, :migration` is deprecated. Call `use Brando.Villain.Migration` instead."
  end

  defmacro __using__([:controller, _] = opts) when is_list(opts) do
    raise "use Brando.Villain with options is deprecated. Call without options."
  end

  @doc """
  Parses `json` (in Villain-format).
  Delegates to the module `villain_parser`, configured in the
  otp_app's config.exs.
  Returns HTML.
  """
  @spec parse(String.t() | [map], Module.t()) :: String.t()
  def parse("", _), do: ""
  def parse(nil, _), do: ""
  def parse(json, parser_mod) when is_binary(json), do: do_parse(Poison.decode!(json), parser_mod)
  def parse(json, parser_mod) when is_list(json), do: do_parse(json, parser_mod)

  defp do_parse(data, parser_mod) do
    html =
      Enum.reduce(data, [], fn data_node, acc ->
        type_atom = String.to_atom(data_node["type"])
        data_node_content = data_node["data"]
        [apply(parser_mod, type_atom, [data_node_content]) | acc]
      end)

    html
    |> Enum.reverse()
    |> Enum.join()
    |> replace_fragment_refs()
    |> replace_identity_refs()
    |> replace_link_refs()
    |> replace_global_refs()
    |> replace_config_refs()
  end

  @doc """
  Map out images
  """
  def map_images(images) do
    Enum.map(images, fn image_record ->
      img_struct = image_record.image

      sizes =
        img_struct.sizes
        |> Enum.map(&{elem(&1, 0), Utils.media_url(elem(&1, 1))})
        |> Enum.into(%{})

      %{
        src: Utils.media_url(img_struct.path),
        thumb: Utils.media_url(Utils.img_url(img_struct, :thumb)),
        sizes: sizes,
        title: img_struct.title,
        credits: img_struct.credits,
        inserted_at: image_record.inserted_at,
        width: img_struct.width,
        height: img_struct.height
      }
    end)
  end

  @doc """
  Rerender page HTML from data.
  """
  def rerender_html(
        %Ecto.Changeset{} = changeset,
        field \\ nil,
        parser_mod \\ Brando.config(Brando.Villain)[:parser]
      ) do
    data_field = (field && field |> to_string |> Kernel.<>("_data") |> String.to_atom()) || :data
    html_field = (field && field |> to_string |> Kernel.<>("_html") |> String.to_atom()) || :html
    data = Ecto.Changeset.get_field(changeset, data_field)

    changeset
    |> Ecto.Changeset.put_change(html_field, Brando.Villain.parse(data, parser_mod))
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
  Rerender HTML from an ID

  ## Example

      rerender_html_from_id({Pages.Page, :data, :html}, 1)

  Will try to rerender html for page with id: 1.

  We treat page fragments special, since they need to propogate to other referencing
  pages and fragments
  """
  @spec rerender_html_from_id(
          {schema :: Module, data_field :: atom, html_field :: atom},
          Integer.t() | String.t()
        ) :: any()
  def rerender_html_from_id({schema, data_field, html_field}, id) do
    parser = Brando.config(Brando.Villain)[:parser]

    query =
      from s in schema,
        where: s.id == ^id

    record = Brando.repo().one(query)
    parsed_data = Brando.Villain.parse(Map.get(record, data_field), parser)

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
  Rerender multiple IDS
  """
  @spec rerender_html_from_ids({Module, atom, atom}, [Integer.t() | String.t()]) :: nil | [any()]
  def rerender_html_from_ids(_, []), do: nil
  def rerender_html_from_ids(args, ids), do: for(id <- ids, do: rerender_html_from_id(args, id))

  @doc """
  Check all posts for missing images
  """
  def check_posts_for_missing_images do
    posts = Brando.repo().all(__MODULE__)

    result =
      Enum.map(posts, fn post ->
        check_post_for_missing_images(post)
      end)

    case result do
      [] -> false
      result -> result
    end
  end

  @doc """
  Check post's villain data field for missing images
  """
  def check_post_for_missing_images(post) do
    image_blocks = Enum.filter(post.data, fn block -> block["type"] == "image" end)

    Enum.reduce(image_blocks, [], fn block, acc ->
      reduced_block =
        Enum.reduce(block["data"]["sizes"], [], fn {_size, path}, acc ->
          (File.exists?(Path.join(["priv", path])) && acc) || {:missing, post, path}
        end)

      case reduced_block do
        [] -> acc
        res -> [res | acc]
      end
    end)
  end

  @doc """
  List all registered Villain fields
  """
  def list_villains do
    {:ok, app_modules} = :application.get_key(Brando.otp_app(), :modules)

    modules = app_modules ++ [Pages.Page, Pages.PageFragment]

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
  Update or create template in DB
  """
  def update_or_create_template(%{"data" => %{"id" => id} = data}) do
    with {:ok, template} <- get_template(id) do
      params = Map.drop(data, ["id"])

      new_template =
        template
        |> Brando.Villain.Template.changeset(params)
        |> Brando.repo().update

      update_template_in_fields(id)

      new_template
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

    query =
      case namespace do
        "all" ->
          query

        _ ->
          from t in query, where: t.namespace == ^namespace
      end

    {:ok, Brando.repo().all(query)}
  end

  @doc """
  Render a Villain data field to HTML and look for variables to interpolate.

  ## Example:

      {:ok, page} = Pages.get_page(1)
      render_villain page.data, %{"link" => "hello"}
  """
  @spec render_villain([map], %{required(String.t()) => String.t()}) :: binary()
  def render_villain(data_field, vars \\ %{})

  def render_villain(data_field, vars) when is_list(data_field) do
    parser_mod = Brando.config(Brando.Villain)[:parser]

    data_field
    |> Brando.Villain.parse(parser_mod)
    |> replace_vars(vars)
  end

  def render_villain(_, _), do: ""

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

  defp replace_fragment_refs(html) do
    Regex.replace(@regex_fragment_ref, html, fn _, parent_key, key, lang ->
      case Pages.get_page_fragment(parent_key, key, lang) do
        {:ok, fragment} ->
          Phoenix.HTML.Safe.to_iodata(fragment)

        {:error, {:page_fragment, :not_found}} ->
          "==> MISSING FRAGMENT: #{parent_key}/#{key}/#{lang} <=="
      end
    end)
  end

  def replace_identity_refs(html) do
    Regex.replace(@regex_identity_ref, html, fn _, key ->
      identity = Brando.Cache.get(:identity)

      Map.get(
        identity,
        String.to_existing_atom(key),
        "==> MISSING IDENTITY KEY: ${IDENTITY:#{key}} <=="
      )
    end)
  end

  def replace_link_refs(html) do
    Regex.replace(@regex_link_ref, html, fn _, name ->
      identity = Brando.Cache.get(:identity)
      link_list = identity.links

      case Enum.find(link_list, &(String.downcase(&1.name) == String.downcase(name))) do
        nil -> "==> MISSING LINK NAME: ${LINK:#{name}} <=="
        link_entry -> link_entry.url
      end
    end)
  end

  def replace_global_refs(html) do
    Regex.replace(@regex_global_ref, html, fn _, key ->
      identity = Brando.Cache.get(:identity)
      global_list = identity.globals

      case Enum.find(global_list, &(String.downcase(&1.key) == String.downcase(key))) do
        nil -> "==> MISSING GLOBAL KEY: ${GLOBAL:#{key}} <=="
        global_entry -> global_entry.value
      end
    end)
  end

  def replace_config_refs(html) do
    Regex.replace(@regex_config_ref, html, fn _, key ->
      identity = Brando.Cache.get(:identity)
      config_list = identity.configs

      case Enum.find(config_list, &(String.downcase(&1.key) == String.downcase(key))) do
        nil -> "==> MISSING CONFIG KEY: ${CONFIG:#{key}} <=="
        config_entry -> config_entry.value
      end
    end)
  end

  defp replace_vars(html, vars) do
    Regex.replace(~r/\${(\w+)}/, html, fn _, match ->
      case Map.get(vars, match, nil) do
        nil -> "${#{match}}"
        val -> val
      end
    end)
  end
end
