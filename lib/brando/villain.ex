defmodule Brando.Villain do
  @moduledoc """
  Interface to Villain HTML editor.
  https://github.com/twined/villain

  # Model

  Model utilities

  ## Usage

      use Brando.Villain, :model

  Add fields to your model:

      schema "my_model" do
        field "header", :string
        villain
      end

  As Ecto 1.1 removed callbacks, we must manually call for HTML generation.
  In your model's `changeset` functions:

      def changeset(model, :create, params) do
        model
        |> cast(params, @required_fields, @optional_fields)
        |> Brando.Villain.HTML.generate_html()
      end

  You can add separate parsers by supplying the parser module as a parameter to the `generate_html`
  function. If not, it will use the parser module given in

  `config :brando, Brando.Villain, :parser`.

  # Migration

  Migration utilities

  ## Usage

      use Brando.Villain, :migration

  Add fields to your model:

      table "bla" do
        villain
      end

  # Controller

  Controller utilities. Expects :image_model and :series_model options.
  Defines `:browse_images`, `:upload_image`, `:image_info` actions.

  ## Usage

      use Brando.Villain, [:controller, [
        image_model: Brando.Image,
        series_model: Brando.ImageSeries]]

  Add routes to your router.ex:

      villain_routes MyController

  """

  @doc false
  def model do
    quote do
      import Brando.Villain.Model, only: [villain: 0]

      @doc """
      Takes the model's `json` field and transforms to `html`.

      This is usually called from your model's `changeset` functions:

          def changeset(model, :create, params) do
            model
            |> cast(params, @required_fields, @optional_fields)
            |> generate_html()
          end
      """
      def generate_html(changeset, parser_mod \\ Brando.config(Brando.Villain)[:parser]) do
        if Ecto.Changeset.get_change(changeset, :data) do
          parsed_data = Brando.Villain.parse(changeset.changes.data, parser_mod)
          Ecto.Changeset.put_change(changeset, :html, parsed_data)
        else
          changeset
        end
      end

      @doc """
      Rerender page HTML from data.
      """
      def rerender_html(changeset) do
        data = Ecto.Changeset.get_field(changeset, :data)

        changeset
        |> Ecto.Changeset.put_change(:html, Brando.Villain.parse(data))
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

  defmodule Model do
    @moduledoc """
    Macro for villain model fields.
    """
    defmacro villain do
      quote do
        Ecto.Schema.field(:data, Brando.Type.Json)
        Ecto.Schema.field(:html, :string)
      end
    end
  end

  @doc false
  def migration do
    quote do
      import Brando.Villain.Migration, only: [villain: 0]
    end
  end

  defmodule Migration do
    @moduledoc """
    Macro for villain migrations.
    """
    defmacro villain do
      quote do
        Ecto.Migration.add(:data, :json)
        Ecto.Migration.add(:html, :text)
      end
    end
  end

  @doc false
  def controller({:image_model, image_model}, {:series_model, series_model}) do
    quote do
      import Ecto.Query
      @doc false
      def browse_images(conn, %{"slug" => series_slug} = params) do
        image_series =
          unquote(series_model)
          |> preload([:image_category, :images])
          |> Brando.repo.get_by(slug: series_slug)

        if image_series do
          image_list = Enum.map(image_series.images, fn image ->
            sizes = Enum.map(image.image.sizes, fn({k, v}) -> {k, Brando.Utils.media_url(v)} end)
            sizes = Enum.into(sizes, %{})

            %{
              src:   Brando.Utils.media_url(image.image.path),
              thumb: Brando.Utils.media_url(Brando.Utils.img_url(image.image, :thumb)),
              sizes: sizes,
              title: image.image.title, credits: image.image.credits
            }
          end)
          json(conn, %{status: "200", images: image_list})
        else
          json(conn, %{status: "204", images: []})
        end
      end

      @doc false
      def upload_image(conn, %{"uid" => uid, "slug" => series_slug} = params) do
        user = Brando.Utils.current_user(conn)

        series =
          unquote(series_model)
          |> preload(:image_category)
          |> Brando.repo.get_by(slug: series_slug)

        if series == nil do
          raise Brando.Exception.UploadError,
                "villain could not find image series `#{series_slug}`. \n\n" <>
                "Make sure it exists before using it as an upload target!\n"
        end

        cfg  = series.cfg || Brando.config(Brando.Images)[:default_config]
        opts = Map.put(%{}, "image_series_id", series.id)

        {:ok, image} = unquote(image_model).check_for_uploads(params, user, cfg, opts)

        sizes     = Enum.map(image.image.sizes, fn({k, v}) -> {k, Brando.Utils.media_url(v)} end)
        sizes_map = Enum.into(sizes, %{})

        json conn,
          %{
            status: "200",
            uid:    uid,
            image: %{
              id:    image.id,
              sizes: sizes_map,
              src:   Brando.Utils.media_url(image.image.path)
            },
            form: %{
              method: "post",
              action: "villain/imagedata/#{image.id}",
              name:   "villain-imagedata",
              fields: [
                %{
                  name:  "title",
                  type:  "text",
                  label: "Tittel",
                  value: ""
                },
                %{
                  name:  "credits",
                  type:  "text",
                  label: "Krediteringer",
                  value: ""
                }
              ]
            }
          }
      end

      @doc false
      def imageseries(conn, %{"series" => series_slug}) do
        series = Brando.repo.first!(
          from is in unquote(series_model),
                join: c in assoc(is, :image_category),
                join: i in assoc(is, :images),
               where: c.slug == "slideshows" and is.slug == ^series_slug,
            order_by: i.sequence,
             preload: [image_category: c, images: i]
        )

        sizes  = Enum.map(series.cfg.sizes, &elem(&1, 0))
        images = Enum.map(series.images, &(&1.image))

        json conn, %{
          status:    200,
          series:    series_slug,
          images:    images,
          sizes:     sizes,
          media_url: Brando.config(:media_url)
        }
      end

      @doc false
      def imageseries(conn, _) do
        series = Brando.repo.all(
          from is in unquote(series_model),
                join: c in assoc(is, :image_category),
               where: c.slug == "slideshows",
            order_by: is.slug,
             preload: [image_category: c]
        )

        series_slugs = Enum.map(series, &(&1.slug))
        json conn, %{status: 200, series: series_slugs}
      end

      @doc false
      def image_info(conn, %{"form" => form, "id" => id, "uid" => uid}) do
        form        = URI.decode_query(form)
        image_model = unquote(image_model)
        image       = Brando.repo.get(image_model, id)

        {:ok, image} =
          image_model.update_image_meta(image, form["title"], form["credits"])

        info = %{
          status:  200,
          id:      id,
          uid:     uid,
          title:   image.image.title,
          credits: image.image.credits,
          link:    form["link"]
        }

        json conn, info
      end
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defmacro __using__([:controller, ctrl_opts] = opts) when is_list(opts) do
    apply(__MODULE__, :controller, ctrl_opts)
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
end
