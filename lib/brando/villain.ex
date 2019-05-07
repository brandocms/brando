# credo:disable-for-this-file
defmodule Brando.Villain do
  @moduledoc """
  Interface to Villain HTML editor.
  """

  require Logger
  alias Brando.Utils
  import Ecto.Query

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
  Rerender HTML from an ID

  ## Example

      rerender_html_from_id({Brando.Pages.Page, :data, :html}, 1)

  Will try to rerender html for page with id: 1.
  """
  @spec rerender_html_from_id({Module, atom, atom}, Integer.t() | String.t()) :: any()
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

    Brando.repo().update(changeset)
  end

  @doc """
  Rerender multiple IDS
  """
  @spec rerender_html_from_ids({Module, atom, atom}, [Integer.t() | String.t()]) :: nil | [any()]
  def rerender_html_from_ids(_, []), do: nil

  def rerender_html_from_ids(args, ids) do
    for id <- ids do
      rerender_html_from_id(args, id)
    end
  end

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

    modules = app_modules ++ [Brando.Pages.Page, Brando.Pages.PageFragment]

    modules
    |> Enum.filter(&({:__villain_fields__, 0} in &1.__info__(:functions)))
    |> Enum.map(& &1.__villain_fields__())
  end

  @doc """
  Update all villain fields in database that has a template with `id`.
  """
  def update_template_in_fields(template_id) do
    result =
      Enum.reduce(list_villains(), fn {schema, fields}, _acc ->
        Enum.reduce(fields, [], fn {_, data_field, html_field}, _acc ->
          ids = list_ids_with_template(schema, data_field, template_id)
          rerender_html_from_ids({schema, data_field, html_field}, ids)
        end)
      end)

    {:ok, result}
  end

  @doc """
  List ids of `schema` records that has `template_id` in `data_field`
  """
  def list_ids_with_template(schema, data_field, template_id) do
    t = [%{type: "template", data: %{id: template_id}}]

    Brando.repo().all(
      from s in schema,
        select: s.id,
        where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^t)
    )
  end

  @doc """
  Get template from DB
  """
  def get_template(id) do
    query =
      from t in Brando.Villain.Template,
        where: t.id == ^id

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

      template
      |> Brando.Villain.Template.changeset(params)
      |> Brando.repo().update
    end

    update_template_in_fields(id)
  end

  def update_or_create_template(%{"data" => params}) do
    %Brando.Villain.Template{}
    |> Brando.Villain.Template.changeset(params)
    |> Brando.repo().insert
  end

  @doc """
  List templates by namespace
  """
  def list_templates(namespace) do
    query = from(t in Brando.Villain.Template, order_by: [asc: t.id, desc: t.updated_at])

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

      {:ok, page} = Brando.Pages.get_page(1)
      render_villain page.data, %{"link" => "hello"}
  """
  @spec render_villain([map], %{required(String.t()) => String.t()}) :: binary()
  def render_villain(data_field, vars \\ %{}) do
    parser_mod = Brando.config(Brando.Villain)[:parser]
    html = Brando.Villain.parse(data_field, parser_mod)

    Regex.replace(~r/\${(\w+)}/, html, fn _, match ->
      case Map.get(vars, match, nil) do
        nil -> "${#{match}}"
        val -> val
      end
    end)
  end
end
