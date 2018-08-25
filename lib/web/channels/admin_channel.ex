defmodule Brando.Mixin.Channels.AdminChannelMixin do
  defmacro __using__(_) do
    quote do
      @doc """
      Join admin channel
      """
      def join("admin", _params, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        socket = assign(socket, :user_id, user.id)
        {:ok, user.id, socket}
      end

      def handle_in("images:delete_images", %{"ids" => ids}, socket) do
        Brando.Images.delete_images(ids)
        {:reply, {:ok, %{code: 200, ids: ids}}, socket}
      end

      def handle_in("images:sequence_images", %{"ids" => ids}, socket) do
        Brando.Image.sequence(ids, Range.new(0, length(ids)))
        {:reply, {:ok, %{code: 200}}, socket}
      end

      def handle_in("images:get_category_id_by_slug", %{"slug" => slug}, socket) do
        {:ok, id} = Brando.Images.get_category_id_by_slug(slug)
        {:reply, {:ok, %{code: 200, category_id: id}}, socket}
      end

      def handle_in("images:create_image_series", params, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, series} = Brando.Images.create_series(params, user)

        {:reply,
         {:ok,
          %{
            code: 200,
            series: Map.merge(series, %{creator: nil, image_category: nil, images: nil})
          }}, socket}
      end

      def handle_in("images:get_category_config", %{"category_id" => category_id}, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, config} = Brando.Images.get_category_config(category_id)
        {:reply, {:ok, %{code: 200, config: config}}, socket}
      end

      def handle_in(
            "images:update_category_config",
            %{"category_id" => category_id, "config" => config},
            socket
          ) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, config} = Brando.Images.update_category_config(category_id, config)
        {:reply, {:ok, %{code: 200}}, socket}
      end

      def handle_in("images:get_series_config", %{"series_id" => series_id}, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, config} = Brando.Images.get_series_config(series_id)
        {:reply, {:ok, %{code: 200, config: config}}, socket}
      end

      def handle_in(
            "images:update_series_config",
            %{"series_id" => series_id, "config" => config},
            socket
          ) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, config} = Brando.Images.update_series_config(series_id, config)
        {:reply, {:ok, %{code: 200}}, socket}
      end

      def handle_in(
            "image:update",
            %{"id" => id, "image" => %{"title" => title, "credits" => credits}},
            socket
          ) do
        image = Brando.Images.get_image!(id)
        {:ok, updated_image} = Brando.Images.update_image_meta(image, title, credits)
        {:reply, {:ok, %{status: 200}}, socket}
      end

      def handle_in("pages:list_parents", _, socket) do
        {:ok, parents} = Brando.Pages.list_parents()
        {:reply, {:ok, %{code: 200, parents: parents}}, socket}
      end

      def handle_in("page:delete", %{"id" => page_id}, socket) do
        Brando.Pages.delete_page(page_id)
        {:reply, {:ok, %{code: 200}}, socket}
      end

      def handle_in("page:duplicate", %{"id" => page_id}, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, new_page} = Brando.Pages.duplicate_page(page_id, user)
        {:reply, {:ok, %{code: 200, page: new_page}}, socket}
      end

      def handle_in("page_fragment:duplicate", %{"id" => page_id}, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, new_fragment} = Brando.Pages.duplicate_page_fragment(page_id, user)
        {:reply, {:ok, %{code: 200, page_fragment: new_fragment}}, socket}
      end
    end
  end
end
