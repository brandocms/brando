defmodule Villain.Controller do
  defmacro __using__(options) do
    model = Keyword.fetch!(options, :model)
    quote do
      @doc false
      def browse_images(conn, _params) do
        images = unquote(model).all
        image_list = Enum.map(images, fn image ->
          %{src: Brando.HTML.media_url(image.image),
            thumb: Brando.HTML.media_url(Brando.Images.Utils.size_dir(image.image, :thumb))}
        end)
        json(conn, %{status: "200", images: image_list})
      end

      @doc false
      def upload_image(conn, %{"uid" => uid} = params) do
        {:ok, image} = unquote(model).check_for_uploads(%{}, params)
        json conn,
          %{status: "200",
            uid: uid,
            image: %{id: image.id, src: Brando.HTML.media_url(image.image)},
            form: %{
              method: "post",
              action: "villain/bildedata/#{image.id}",
              name: "villain-imagedata",
              fields: [
                %{name: "title",
                  type: "text",
                  label: "Tittel",
                  value: ""},
                %{name: "credits",
                  type: "text",
                  label: "Krediteringer",
                  value: ""
                }
              ]
            }
          }
      end

      @doc false
      def image_info(conn, %{"form" => form, "id" => id, "uid" => uid}) do
        form = URI.decode_query(form)
        {:ok, image} = unquote(model).update(unquote(model).get(id: id), form)
        json conn,
          %{status: 200, id: id, uid: uid,
            title: image.title, credits: image.credits}
      end
    end
  end
end