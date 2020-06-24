defmodule Brando.Mixin.Channels.AdminChannelMixin do
  @keys [
    "datasource:list_available_entries",
    "datasource:list_modules",
    "datasource:list_module_keys",
    "image:get",
    "images:delete_images",
    "images:sequence_images",
    "images:get_category_id_by_slug",
    "images:create_image_series",
    "images:get_category_config",
    "images:update_category_config",
    "images:propagate_category_config",
    "images:get_series_config",
    "images:update_series_config",
    "images:rerender_image_series",
    "pages:list_parents",
    "pages:list_templates",
    "pages:sequence_pages",
    "page:delete",
    "page:rerender",
    "page:duplicate",
    "page:rerender_all",
    "page_fragments:sequence_fragments",
    "page_fragment:rerender",
    "page_fragment:duplicate",
    "page_fragment:rerender_all",
    "config:get",
    "config:set",
    "config:add_key",
    "user:deactivate",
    "user:activate",
    "templates:list_templates",
    "livepreview:initialize",
    "livepreview:render"
  ]

  defmacro __using__(_) do
    quote do
      unquote(join())
      unquote(handle_ins())
    end
  end

  defp join do
    quote do
      def join("admin", params, socket),
        do: Brando.Mixin.Channels.AdminChannelMixin.do_join("admin", params, socket)
    end
  end

  defp handle_ins do
    for key <- @keys do
      quote do
        def handle_in(unquote(key), params, socket),
          do: Brando.Mixin.Channels.AdminChannelMixin.do_handle_in(unquote(key), params, socket)
      end
    end
  end

  def do_join("admin", _params, socket) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    socket = Phoenix.Socket.assign(socket, :user_id, user.id)
    {:ok, user.id, socket}
  end

  def do_handle_in("images:delete_images", %{"ids" => ids}, socket) do
    Brando.Images.delete_images(ids)
    {:reply, {:ok, %{code: 200, ids: ids}}, socket}
  end

  def do_handle_in("images:sequence_images", params, socket) do
    Brando.Image.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("images:propagate_category_config", %{"category_id" => category_id}, socket) do
    Brando.Images.propagate_category_config(category_id)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("images:get_category_id_by_slug", %{"slug" => slug}, socket) do
    case Brando.Images.get_category_id_by_slug(slug) do
      {:ok, id} ->
        {:reply, {:ok, %{code: 200, category_id: id}}, socket}

      {:error, {:image_category, :not_found}} ->
        {:reply, {:error, %{code: 404, message: "Category not found"}}, socket}
    end
  end

  def do_handle_in("images:create_image_series", params, socket) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    {:ok, series} = Brando.Images.create_series(params, user)

    {:reply,
     {:ok,
      %{
        code: 200,
        series: Map.merge(series, %{creator: nil, image_category: nil, images: nil})
      }}, socket}
  end

  def do_handle_in("images:get_category_config", %{"category_id" => category_id}, socket) do
    {:ok, config} = Brando.Images.get_category_config(category_id)
    {:reply, {:ok, %{code: 200, config: config}}, socket}
  end

  def do_handle_in("images:get_category_config", %{"category_slug" => category_slug}, socket) do
    {:ok, config} = Brando.Images.get_category_config_by_slug(category_slug)
    {:reply, {:ok, %{code: 200, config: config}}, socket}
  end

  def do_handle_in(
        "images:update_category_config",
        %{"category_id" => category_id, "config" => config},
        socket
      ) do
    {:ok, _} = Brando.Images.update_category_config(category_id, config)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("images:get_series_config", %{"series_id" => series_id}, socket) do
    {:ok, config} = Brando.Images.get_series_config(series_id)
    {:reply, {:ok, %{code: 200, config: config}}, socket}
  end

  def do_handle_in(
        "images:update_series_config",
        %{"series_id" => series_id, "config" => config},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    {:ok, _} = Brando.Images.update_series_config(series_id, config, user)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "images:rerender_image_category",
        %{"category_id" => category_id},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    Brando.Images.Processing.recreate_sizes_for_image_category(category_id, user)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "images:rerender_image_series",
        %{"series_id" => series_id},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    Brando.Images.Processing.recreate_sizes_for_image_series(series_id, user)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "image:get",
        %{"id" => id},
        socket
      ) do
    image = Brando.Images.get_image!(id)
    {:reply, {:ok, %{status: 200, image: image.image}}, socket}
  end

  def do_handle_in("pages:list_parents", _, socket) do
    {:ok, parents} = Brando.Pages.list_parents()
    {:reply, {:ok, %{code: 200, parents: parents}}, socket}
  end

  def do_handle_in("pages:list_templates", _, socket) do
    {:ok, templates} = Brando.Pages.list_templates()
    {:reply, {:ok, %{code: 200, templates: templates}}, socket}
  end

  def do_handle_in("pages:sequence_pages", params, socket) do
    Brando.Pages.Page.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page:delete", %{"id" => page_id}, socket) do
    Brando.Pages.delete_page(page_id)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page:duplicate", %{"id" => page_id}, socket) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    {:ok, new_page} = Brando.Pages.duplicate_page(page_id, user)
    {:reply, {:ok, %{code: 200, page: new_page}}, socket}
  end

  def do_handle_in("page:rerender", %{"id" => page_id}, socket) do
    Brando.Pages.rerender_page(String.to_integer(page_id))
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page:rerender_all", _, socket) do
    Brando.Pages.rerender_pages()
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page_fragments:sequence_fragments", params, socket) do
    Brando.Pages.PageFragment.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page_fragment:duplicate", %{"id" => page_id}, socket) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    {:ok, new_fragment} = Brando.Pages.duplicate_page_fragment(page_id, user)
    {:reply, {:ok, %{code: 200, page_fragment: new_fragment}}, socket}
  end

  def do_handle_in("page_fragment:rerender", %{"id" => fragment_id}, socket) do
    Brando.Pages.rerender_fragment(String.to_integer(fragment_id))
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page_fragment:rerender_all", _, socket) do
    Brando.Pages.rerender_fragments()
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("user:deactivate", %{"user_id" => user_id}, socket) do
    Brando.Users.set_active(user_id, false)
    {:reply, {:ok, %{code: 200, user_id: user_id}}, socket}
  end

  def do_handle_in("user:activate", %{"user_id" => user_id}, socket) do
    Brando.Users.set_active(user_id, true)
    {:reply, {:ok, %{code: 200, user_id: user_id}}, socket}
  end

  def do_handle_in("datasource:list_modules", _, socket) do
    {:ok, available_modules} = Brando.Datasource.list_datasources()
    available_modules = Enum.map(available_modules, &Map.put(%{}, :module, &1))
    {:reply, {:ok, %{code: 200, available_modules: available_modules}}, socket}
  end

  def do_handle_in("datasource:list_module_keys", %{"module" => module}, socket) do
    {:ok, available_keys} = Brando.Datasource.list_datasource_keys(module)
    {:reply, {:ok, %{code: 200, available_module_keys: available_keys}}, socket}
  end

  def do_handle_in(
        "datasource:list_available_entries",
        %{"module" => module, "query" => query},
        socket
      ) do
    {:ok, entries} = Brando.Datasource.list_selection(module, query, nil)
    {:reply, {:ok, %{code: 200, available_entries: entries}}, socket}
  end

  def do_handle_in("templates:list_templates", _, socket) do
    {:ok, templates} = Brando.Villain.list_templates("all")
    templates = Enum.map(templates, &%{id: &1.id, name: "#{&1.namespace} - #{&1.name}"})
    {:reply, {:ok, %{code: 200, templates: templates}}, socket}
  end

  # Live preview
  def do_handle_in(
        "livepreview:initialize",
        %{"schema" => schema, "entry" => entry, "key" => key, "prop" => prop},
        socket
      ) do
    cache_key = Brando.LivePreview.initialize(schema, entry, key, prop)
    {:reply, {:ok, %{code: 200, cache_key: cache_key}}, socket}
  end

  def do_handle_in(
        "livepreview:render",
        %{
          "schema" => schema,
          "entry" => entry,
          "key" => key,
          "prop" => prop,
          "cache_key" => cache_key
        },
        socket
      ) do
    Brando.LivePreview.update(schema, entry, key, prop, cache_key)
    {:reply, {:ok, %{code: 200, cache_key: cache_key}}, socket}
  end
end
