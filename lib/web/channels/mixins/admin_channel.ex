require Protocol

Protocol.derive(Jason.Encoder, Oban.Job,
  only: ~w(id meta tags worker state scheduled_at attempt args)a
)

defmodule Brando.Mixin.Channels.AdminChannelMixin do
  alias Brando.Images
  alias Brando.Navigation
  alias Brando.Pages
  alias Brando.Publisher
  alias Brando.Revisions
  alias Brando.Villain

  @keys [
    "cache:list",
    "cache:empty",
    "config:get",
    "config:set",
    "config:add_key",
    "datasource:list_available_entries",
    "datasource:list_modules",
    "datasource:list_module_keys",
    "images:get_image",
    "images:delete_images",
    "images:sequence_images",
    "images:get_category_id_by_slug",
    "images:create_image_series",
    "images:get_category_config",
    "images:update_category_config",
    "images:propagate_category_config",
    "images:get_series_config",
    "images:update_series_config",
    "images:rerender_image",
    "images:rerender_image_series",
    "images:rerender_image_category",
    "livepreview:initialize",
    "livepreview:render",
    "menus:sequence_menus",
    "oembed:get",
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
    "publisher:list",
    "publisher:delete_job",
    "revision:activate",
    "revision:delete",
    "revision:schedule",
    "revisions:purge_inactive",
    "sitemap:exists",
    "sitemap:generate",
    "villain:list_modules",
    "villain:sequence_modules",
    "user:deactivate",
    "user:activate",
    "user:state"
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
    Images.delete_images(ids)
    {:reply, {:ok, %{code: 200, ids: ids}}, socket}
  end

  def do_handle_in("images:sequence_images", params, socket) do
    Brando.Image.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("images:propagate_category_config", %{"category_id" => category_id}, socket) do
    Images.propagate_category_config(category_id)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("images:get_category_id_by_slug", %{"slug" => slug}, socket) do
    case Images.get_category_id_by_slug(slug) do
      {:ok, id} ->
        {:reply, {:ok, %{code: 200, category_id: id}}, socket}

      {:error, {:image_category, :not_found}} ->
        {:reply, {:error, %{code: 404, message: "Category not found"}}, socket}
    end
  end

  def do_handle_in("images:create_image_series", params, socket) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    {:ok, series} = Images.create_series(params, user)

    {:reply,
     {:ok,
      %{
        code: 200,
        series: Map.merge(series, %{creator: nil, image_category: nil, images: nil})
      }}, socket}
  end

  def do_handle_in("images:get_category_config", %{"category_id" => category_id}, socket) do
    {:ok, config} = Images.get_category_config(category_id)
    {:reply, {:ok, %{code: 200, config: config}}, socket}
  end

  def do_handle_in("images:get_category_config", %{"category_slug" => category_slug}, socket) do
    {:ok, config} = Images.get_category_config_by_slug(category_slug)
    {:reply, {:ok, %{code: 200, config: config}}, socket}
  end

  def do_handle_in(
        "images:update_category_config",
        %{"category_id" => category_id, "config" => config},
        socket
      ) do
    {:ok, _} = Images.update_category_config(category_id, config)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("images:get_series_config", %{"series_id" => series_id}, socket) do
    {:ok, config} = Images.get_series_config(series_id)
    {:reply, {:ok, %{code: 200, config: config}}, socket}
  end

  def do_handle_in(
        "images:update_series_config",
        %{"series_id" => series_id, "config" => config},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    {:ok, _} = Images.update_series_config(series_id, config, user)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "images:rerender_image_category",
        %{"category_id" => category_id},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    Images.Processing.recreate_sizes_for_category(category_id, user)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "images:rerender_image_series",
        %{"series_id" => series_id},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    Images.Processing.recreate_sizes_for_series(series_id, user)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "images:rerender_image",
        %{"id" => id},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    {:ok, img} = Images.get_image(id)
    Images.Processing.recreate_sizes_for_image(img, user)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "images:get_image",
        %{"image_id" => id},
        socket
      ) do
    image = Images.get_image!(id)
    {:reply, {:ok, %{code: 200, image: image.image}}, socket}
  end

  def do_handle_in("oembed:get", %{"source" => source, "url" => url}, socket) do
    {:ok, result} = Brando.OEmbed.get(source, url)
    {:reply, {:ok, %{code: 200, result: result}}, socket}
  end

  def do_handle_in("pages:list_parents", _, socket) do
    {:ok, parents} = Pages.list_parents()
    {:reply, {:ok, %{code: 200, parents: parents}}, socket}
  end

  def do_handle_in("pages:list_templates", _, socket) do
    {:ok, templates} = Pages.list_templates()
    {:reply, {:ok, %{code: 200, templates: templates}}, socket}
  end

  def do_handle_in("pages:sequence_pages", params, socket) do
    Pages.Page.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page:delete", %{"id" => page_id}, socket) do
    Pages.delete_page(page_id)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page:duplicate", %{"id" => page_id}, socket) do
    {:ok, new_page} = Pages.duplicate_page(page_id)
    {:reply, {:ok, %{code: 200, page: new_page}}, socket}
  end

  def do_handle_in("page:rerender", %{"id" => page_id}, socket) do
    Pages.rerender_page(String.to_integer(page_id))
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page:rerender_all", _, socket) do
    Pages.rerender_pages()
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page_fragments:sequence_fragments", params, socket) do
    Pages.PageFragment.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page_fragment:duplicate", %{"id" => page_id}, socket) do
    case Pages.duplicate_page_fragment(page_id) do
      {:ok, new_fragment} ->
        {:reply, {:ok, %{code: 200, page_fragment: new_fragment}}, socket}

      {:error, {:page_fragment, :not_found}} ->
        {:reply, {:error, %{code: 400, message: "Fragment not found!"}}, socket}
    end
  end

  def do_handle_in("page_fragment:rerender", %{"id" => fragment_id}, socket) do
    Pages.rerender_fragment(String.to_integer(fragment_id))
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("page_fragment:rerender_all", _, socket) do
    Pages.rerender_fragments()
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "revision:activate",
        %{"schema" => schema, "id" => id, "revision" => revision},
        socket
      ) do
    Revisions.set_revision(Module.concat([schema]), id, revision)

    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "revision:delete",
        %{"schema" => schema, "id" => id, "revision" => revision},
        socket
      ) do
    Revisions.delete_revision(Module.concat([schema]), id, revision)

    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "revision:schedule",
        %{"schema" => schema, "id" => id, "revision" => revision, "publish_at" => publish_at},
        socket
      ) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    Publisher.schedule_revision(Module.concat([schema]), id, revision, publish_at, user)

    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in(
        "revisions:purge_inactive",
        %{"schema" => schema, "id" => id},
        socket
      ) do
    Revisions.purge_revisions(Module.concat([schema]), id)

    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("sitemap:exists", _, socket) do
    {:reply, {:ok, %{sitemap: Brando.Sitemap.exists?()}}, socket}
  end

  def do_handle_in("sitemap:generate", _, socket) do
    Brando.sitemap().generate_sitemap()
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("menus:sequence_menus", params, socket) do
    Navigation.Menu.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  # Set user presence state active or not
  def do_handle_in("user:state", %{"active" => active}, socket) do
    Brando.presence().update(socket, socket.assigns.user_id, %{
      online_at: inspect(System.system_time(:second)),
      active: active
    })

    {:reply, :ok, socket}
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

  def do_handle_in("villain:list_modules", %{"namespace" => namespace}, socket) do
    {:ok, modules} = Villain.list_modules(%{filter: %{namespace: namespace}})
    formatted_modules = Enum.map(modules, fn mod -> %{type: "module", data: mod} end)
    {:reply, {:ok, %{code: 200, modules: formatted_modules}}, socket}
  end

  def do_handle_in("villain:sequence_modules", params, socket) do
    Villain.Module.sequence(params)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("cache:list", _, socket) do
    {:ok, query_caches} = Cachex.keys(:query)
    {:reply, {:ok, %{code: 200, caches: %{query: query_caches}}}, socket}
  end

  def do_handle_in("cache:empty", _, socket) do
    Cachex.clear(:query)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  def do_handle_in("publisher:list", _, socket) do
    {:ok, jobs} = Publisher.list_jobs()
    {:reply, {:ok, %{code: 200, jobs: jobs}}, socket}
  end

  def do_handle_in("publisher:delete_job", %{"job" => %{"id" => job_id}}, socket) do
    Publisher.delete_job(job_id)
    {:reply, {:ok, %{code: 200}}, socket}
  end

  # Live preview
  def do_handle_in(
        "livepreview:initialize",
        %{"schema" => schema, "entry" => entry, "key" => key, "prop" => prop},
        socket
      ) do
    entry = Brando.Utils.snake_case(entry)

    case Brando.LivePreview.initialize(schema, entry, key, prop) do
      {:ok, cache_key} ->
        {:reply, {:ok, %{code: 200, cache_key: cache_key}}, socket}

      {:error, err} ->
        {:reply, {:error, %{code: 404, message: err}}, socket}
    end
  end

  def do_handle_in(
        "livepreview:render",
        %{
          "schema" => schema,
          "entry" => camel_cased_entry_diff,
          "key" => key,
          "prop" => prop,
          "cache_key" => cache_key
        },
        socket
      ) do
    entry_diff = Brando.Utils.snake_case(camel_cased_entry_diff)
    Brando.LivePreview.update(schema, entry_diff, key, prop, cache_key)
    {:reply, {:ok, %{code: 200, cache_key: cache_key}}, socket}
  end
end
