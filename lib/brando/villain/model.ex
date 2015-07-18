defmodule Brando.Villain.Model do
  @moduledoc """
  Villain model tools

  ## Usage

      use Brando.Villain.Model

  Add fields to your model:

      schema "my_model" do
        field "header", :string
        villain
      end

  """

  defmacro __using__(_) do
    quote do
      import Brando.Villain.Model

      before_insert :generate_html
      before_update :generate_html

      @doc """
      Callback from before_insert/before_update to generate HTML.
      Takes the model's `json` field and transforms to `html`.
      """
      def generate_html(changeset) do
        if Ecto.Changeset.get_change(changeset, :data) do
          changeset |> Ecto.Changeset.put_change(:html, Brando.Villain.parse(changeset.changes.data))
        else
          changeset
        end
      end

      @doc """
      Check all posts for missing images
      """
      def check_posts_for_missing_images do
        posts = __MODULE__ |> Brando.repo.all
        result = Enum.reduce posts, [], fn(post, acc) ->
          check_post_for_missing_images(post)
        end
        case result do
          [] -> false
          result -> result
        end
      end

      @doc """
      Check post's villain data field for missing images
      """
      def check_post_for_missing_images(post) do
        image_blocks =
          post.data
          |> Enum.filter(fn(block) -> block["type"] == "image" end)

        Enum.reduce image_blocks, [], fn(image_block, acc) ->
          reduced_block =
            Enum.reduce image_block["data"]["sizes"], [], fn({_size, path}, acc) ->
              case File.exists?(Path.join(["priv", path])) do
                true  -> acc
                false -> {:missing, post, path}
              end
            end
          case reduced_block do
            []  -> acc
            res -> [res|acc]
          end
        end
      end
    end
  end

  defmacro villain do
    quote do
      Ecto.Schema.field(:data, Brando.Type.Json)
      Ecto.Schema.field(:html, :string)
    end
  end
end