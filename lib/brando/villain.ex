# credo:disable-for-this-file
defmodule Brando.Villain do
  @moduledoc """
  Interface to Villain HTML editor.
  https://github.com/twined/villain

  # Schema

  Schema utilities

  ## Usage

      use Brando.Villain, :schema

  Add fields to your schema:

      schema "my_schema" do
        field "header", :string
        villain :biography
      end

  As Ecto 1.1 removed callbacks, we must manually call for HTML generation.
  In your schema's `changeset` functions:

      def changeset(schema, :create, params) do
        schema
        |> cast(params, @required_fields, @optional_fields)
        |> Brando.Villain.HTML.generate_html()
      end

  You can add separate parsers by supplying the parser module as a parameter to the `generate_html`
  function or `rerender_html` funtion. If not, it will use the parser module given in

      config :brando, Brando.Villain, :parser

  # Migration

  Migration utilities

  ## Usage

      use Brando.Villain, :migration

  Add fields to your schema:

      table "bla" do
        villain
      end

  # Controller

  Defines `:browse_images`, `:upload_image`, `:image_info` actions.

  ## Usage

      use Brando.Villain, :controller

  Add routes to your router.ex:

      villain_routes MyController

  """
  import Brando.Utils, only: [img_url: 2, media_url: 1]

  @doc false
  def schema do
    quote do
      import Brando.Villain.Schema, only: [villain: 0, villain: 1]

      @doc """
      Takes the schema's `json` field and transforms to `html`.

      This is usually called from your schema's `changeset` functions:

          def changeset(schema, :create, params) do
            schema
            |> cast(params, @required_fields, @optional_fields)
            |> generate_html()
          end
      """
      def generate_html(changeset, field \\ nil, parser_mod \\ Brando.config(Brando.Villain)[:parser]) do
        data_field = field && (field |> to_string |> Kernel.<>("_data") |> String.to_atom) || :data
        html_field = field && (field |> to_string |> Kernel.<>("_html") |> String.to_atom) || :html

        if Ecto.Changeset.get_change(changeset, data_field) do
          parsed_data = Brando.Villain.parse(Map.get(changeset.changes, data_field), parser_mod)
          Ecto.Changeset.put_change(changeset, html_field, parsed_data)
        else
          changeset
        end
      end

      @doc """
      Rerender page HTML from data.
      """
      def rerender_html(changeset, field \\ nil, parser_mod \\ Brando.config(Brando.Villain)[:parser]) do
        data_field = field && field |> to_string |> Kernel.<>("_data") |> String.to_atom || :data
        html_field = field && field |> to_string |> Kernel.<>("_html") |> String.to_atom || :html

        data = Ecto.Changeset.get_field(changeset, data_field)

        changeset
        |> Ecto.Changeset.put_change(html_field, Brando.Villain.parse(data, parser_mod))
        |> Brando.repo.update!
      end

      @doc """
      Check all posts for missing images
      """
      def check_posts_for_missing_images do
        posts = Brando.repo.all(__MODULE__)
        result = Enum.reduce posts, [], fn(post, acc) ->
          check_post_for_missing_images(post)
        end

        case result do
          []     -> false
          result -> result
        end
      end

      @doc """
      Check post's villain data field for missing images
      """
      def check_post_for_missing_images(post) do
        image_blocks = Enum.filter post.data, fn(block) -> block["type"] == "image" end

        Enum.reduce(image_blocks, [], fn(block, acc) ->
          reduced_block =
            Enum.reduce(block["data"]["sizes"], [], fn({_size, path}, acc) ->
              File.exists?(Path.join(["priv", path])) && acc || {:missing, post, path}
            end)
          case reduced_block do
            []  -> acc
            res -> [res|acc]
          end
        end)
      end
    end
  end

  defmodule Schema do
    @moduledoc """
    Macro for villain schema fields.
    """
    defmacro villain(field \\ nil) do
      data_field = field && field |> to_string |> Kernel.<>("_data") |> String.to_atom || :data
      html_field = field && field |> to_string |> Kernel.<>("_html") |> String.to_atom || :html
      quote do
        Ecto.Schema.field(unquote(data_field), Brando.Type.Json)
        Ecto.Schema.field(unquote(html_field), :string)
      end
    end
  end

  @doc false
  def migration do
    quote do
      import Brando.Villain.Migration, only: [villain: 0, villain: 1]
    end
  end

  defmodule Migration do
    @moduledoc """
    Macro for villain migrations.
    """
    defmacro villain(field \\ nil) do
      data_field = field && field |> to_string |> Kernel.<>("_data") |> String.to_atom || :data
      html_field = field && field |> to_string |> Kernel.<>("_html") |> String.to_atom || :html
      quote do
        Ecto.Migration.add(unquote(data_field), :json)
        Ecto.Migration.add(unquote(html_field), :text)
      end
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
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
  @spec parse(String.t, Module.t) :: String.t
  def parse("", _), do: ""
  def parse(nil, _), do: ""
  def parse(json, parser_mod) when is_binary(json), do:
    do_parse(Poison.decode!(json), parser_mod)
  def parse(json,parser_mod) when is_list(json), do:
    do_parse(json, parser_mod)

  defp do_parse(data, parser_mod) do
    html =
      Enum.reduce(data, [], fn(data_node, acc) ->
        type_atom = String.to_atom(data_node["type"])
        data_node_content = data_node["data"]
        [apply(parser_mod, type_atom, [data_node_content])|acc]
      end)

    html
    |> Enum.reverse
    |> Enum.join
  end

  def map_images(images) do
    Enum.map(images, fn image_record ->
      img_field = image_record.image

      sizes =
        img_field.sizes
        |> Enum.map(&({elem(&1, 0), media_url(elem(&1, 1))}))
        |> Enum.into(%{})

      %{
        src:     media_url(img_field.path),
        thumb:   media_url(img_url(img_field, :thumb)),
        sizes:   sizes,
        title:   img_field.title,
        credits: img_field.credits
      }
    end)
  end
end
