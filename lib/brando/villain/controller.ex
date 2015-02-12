defmodule Villain.Controller do
  defmacro __using__(options) do
    model = Keyword.fetch!(options, :model)
    struct = Keyword.fetch!(options, :struct)
    quote do
      @doc false
      def browse_images(conn, _params) do
        images = unquote(model).all
        image_list = Enum.map(images, fn image ->
          %{src: Brando.HTML.media_url(image.image),
            thumb: Brando.HTML.media_url(Brando.Mugshots.Utils.size_dir(image.image, :thumb))}
        end)
        json(conn, %{status: "200", images: image_list})
      end

      @doc false
      def upload_image(conn, %{"uid" => uid} = params) do
        {:ok, [image]} = unquote(model).check_for_uploads(unquote(struct), params)
        json conn,
          %{status: "200",
            uid: uid,
            image: %{id: image.id, src: Brando.HTML.media_url(image.image)},
            form: %{
              method: "post",
              action: "last-opp/bildedata/",
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
    end
  end
end