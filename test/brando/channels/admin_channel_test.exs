defmodule Brando.AdminChannelTest do
  use Brando.ChannelCase, async: false
  use ExUnit.Case, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Brando.Factory
  alias BrandoIntegration.AdminChannel
  alias BrandoIntegration.AdminSocket
  alias BrandoIntegrationWeb.Endpoint

  @endpoint Endpoint
  @long_timeout 5000

  setup do
    user = Factory.insert(:random_user)
    socket = socket(AdminSocket, "admin", %{})
    socket = Guardian.Phoenix.Socket.put_current_resource(socket, user)
    {:ok, socket} = AdminSocket.connect(%{"guardian_token" => "blerg"}, socket)
    {:ok, _, socket} = subscribe_and_join(socket, AdminChannel, "admin", %{})

    {:ok, %{socket: socket, user: user}}
  end

  #
  # IMAGES
  #

  describe "images" do
    test "images:delete_images", %{socket: socket} do
      i1 = Factory.insert(:image)
      i2 = Factory.insert(:image)
      ids = [i1.id, i2.id]

      ref = push(socket, "images:delete_images", %{"ids" => ids})
      assert_reply ref, :ok, %{code: 200, ids: ^ids}
    end

    test "images:sequence_images", %{socket: socket} do
      i1 = Factory.insert(:image)
      i2 = Factory.insert(:image)
      i3 = Factory.insert(:image)

      assert i1.sequence == 0
      assert i2.sequence == 0
      assert i3.sequence == 0

      ref = push(socket, "images:sequence_images", %{"ids" => [i2.id, i3.id, i1.id]})
      assert_reply ref, :ok, %{code: 200}

      q =
        from t in Brando.Image,
          order_by: :sequence,
          select: [t.id]

      images = Brando.repo().all(q)

      assert images == [[i2.id], [i3.id], [i1.id]]
    end

    test "images:propagate_category_config", %{socket: socket} do
      c1 = Factory.insert(:image_category)
      s1 = Factory.insert(:image_series, image_category: c1)
      _ = Factory.insert(:image, image_series_id: s1.id)

      ref = push(socket, "images:propagate_category_config", %{"category_id" => c1.id})
      assert_reply ref, :ok, %{code: 200}
    end

    test "images:get_category_id_by_slug", %{socket: socket} do
      c1 = Factory.insert(:image_category, name: "test", slug: "test")
      ref = push(socket, "images:get_category_id_by_slug", %{"slug" => "non_existing"})
      assert_reply ref, :error, %{code: 404, message: "Category not found"}

      ref = push(socket, "images:get_category_id_by_slug", %{"slug" => c1.slug})
      assert_reply ref, :ok, %{code: 200}
    end

    test "images:create_image_series", %{socket: socket} do
      c1 = Factory.insert(:image_category)
      params = %{"name" => "new series", "slug" => "new-series", "image_category_id" => c1.id}
      ref = push(socket, "images:create_image_series", params)
      assert_reply ref, :ok, %{code: 200}
    end

    test "images:get_category_config", %{socket: socket} do
      c1 = Factory.insert(:image_category)
      ref = push(socket, "images:get_category_config", %{"category_id" => c1.id})
      assert_reply ref, :ok, %{code: 200, config: cfg}
      assert cfg == c1.cfg

      ref = push(socket, "images:get_category_config", %{"category_slug" => c1.slug})
      assert_reply ref, :ok, %{code: 200, config: cfg}
      assert cfg == c1.cfg
    end

    test "images:update_category_config", %{socket: socket} do
      c1 = Factory.insert(:image_category)
      new_cfg = Map.put(c1.cfg, :random_filename, true)

      ref =
        push(socket, "images:update_category_config", %{
          "category_id" => c1.id,
          "config" => new_cfg
        })

      assert_reply ref, :ok, %{code: 200}

      {:ok, c2} = Brando.Images.get_image_category(%{matches: [id: c1.id]})
      assert c1.cfg.random_filename == false
      assert c2.cfg.random_filename == true
    end

    test "images:get_series_config", %{socket: socket} do
      c1 = Factory.insert(:image_series)
      ref = push(socket, "images:get_series_config", %{"series_id" => c1.id})
      assert_reply ref, :ok, %{code: 200, config: cfg}
      assert cfg == c1.cfg
    end

    test "images:update_series_config", %{socket: socket} do
      c1 = Factory.insert(:image_series)
      new_cfg = Map.put(c1.cfg, :random_filename, true)

      ref =
        push(socket, "images:update_series_config", %{"series_id" => c1.id, "config" => new_cfg})

      assert_reply ref, :ok, %{code: 200}

      {:ok, c2} = Brando.Images.get_image_series(%{matches: [id: c1.id]})
      assert c1.cfg.random_filename == false
      assert c2.cfg.random_filename == true
    end

    test "images:rerender_image_category", %{socket: socket} do
      c1 = Factory.insert(:image_category)
      s1 = Factory.insert(:image_series, image_category: c1)
      _i1 = Factory.insert(:image, image_series_id: s1.id)

      fixture = Path.join([Path.expand("../../", __DIR__), "fixtures", "sample.jpg"])
      target = Path.join([Brando.Images.Utils.media_path(s1.cfg.upload_path), "1.jpg"])
      File.mkdir_p!(Path.dirname(target))

      File.cp_r!(
        fixture,
        target
      )

      ref = push(socket, "images:rerender_image_category", %{"category_id" => c1.id})
      assert_reply ref, :ok, %{code: 200}, @long_timeout
    end

    test "images:rerender_image_series", %{socket: socket} do
      c1 = Factory.insert(:image_category)
      s1 = Factory.insert(:image_series, image_category: c1)
      _ = Factory.insert(:image, image_series_id: s1.id)

      fixture = Path.join([Path.expand("../../", __DIR__), "fixtures", "sample.jpg"])
      target = Path.join([Brando.Images.Utils.media_path(s1.cfg.upload_path), "1.jpg"])
      File.mkdir_p!(Path.dirname(target))

      File.cp_r!(
        fixture,
        target
      )

      ref = push(socket, "images:rerender_image_series", %{"series_id" => s1.id})
      assert_reply ref, :ok, %{code: 200}, @long_timeout
    end

    test "images:get_image", %{socket: socket} do
      i1 = Factory.insert(:image)

      ref = push(socket, "images:get_image", %{"image_id" => i1.id})
      assert_reply ref, :ok, %{code: 200, image: image}
      assert image.path == "image/1.jpg"
    end
  end

  #
  # PAGES
  #

  describe "pages" do
    test "pages:list_parents", %{socket: socket} do
      ref = push(socket, "pages:list_parents", %{})
      assert_reply ref, :ok, %{code: 200, parents: [%{name: "–", value: nil}]}

      Factory.insert(:page)

      ref = push(socket, "pages:list_parents", %{})

      assert_reply ref, :ok, %{
        code: 200,
        parents: [%{name: "–", value: nil}, %{name: _}]
      }
    end

    test "pages:list_templates", %{socket: socket} do
      ref = push(socket, "pages:list_templates", %{})

      assert_reply ref, :ok, %{
        code: 200,
        templates: [%{name: "index", value: "index.html"}, %{name: "show", value: "show.html"}]
      }
    end

    test "pages:sequence_pages", %{socket: socket} do
      p1 = Factory.insert(:page)
      p2 = Factory.insert(:page)
      p3 = Factory.insert(:page)

      assert p1.sequence == 0
      assert p2.sequence == 0
      assert p3.sequence == 0

      ref = push(socket, "pages:sequence_pages", %{"ids" => [p2.id, p3.id, p1.id]})
      assert_reply ref, :ok, %{code: 200}

      q =
        from t in Brando.Pages.Page,
          order_by: :sequence,
          select: [t.id]

      pages = Brando.repo().all(q)

      assert pages == [[p2.id], [p3.id], [p1.id]]
    end

    test "page:delete", %{socket: socket} do
      p1 = Factory.insert(:page)

      ref = push(socket, "page:delete", %{"id" => p1.id})
      assert_reply ref, :ok, %{code: 200}
    end

    test "page:duplicate", %{socket: socket} do
      p1 = Factory.insert(:page, data: [])

      ref = push(socket, "page:duplicate", %{"id" => p1.id})
      assert_reply ref, :ok, %{code: 200, page: page}
      refute page.id == p1
    end

    test "page:rerender", %{socket: socket} do
      p1 =
        Factory.insert(:page,
          data: [
            %{
              "type" => "text",
              "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
            }
          ]
        )

      ref = push(socket, "page:rerender", %{"id" => to_string(p1.id)})
      assert_reply ref, :ok, %{code: 200}
    end

    test "page:rerender_all", %{socket: socket} do
      _ =
        Factory.insert(:page,
          data: [
            %{
              "type" => "text",
              "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
            }
          ]
        )

      ref = push(socket, "page:rerender_all", %{})
      assert_reply ref, :ok, %{code: 200}
    end

    test "page_fragments:sequence_fragments", %{socket: socket} do
      p1 = Factory.insert(:page_fragment)
      p2 = Factory.insert(:page_fragment)
      p3 = Factory.insert(:page_fragment)

      assert p1.sequence == 0
      assert p2.sequence == 0
      assert p3.sequence == 0

      ref = push(socket, "page_fragments:sequence_fragments", %{"ids" => [p2.id, p3.id, p1.id]})
      assert_reply ref, :ok, %{code: 200}

      q =
        from t in Brando.Pages.PageFragment,
          order_by: :sequence,
          select: [t.id]

      pages = Brando.repo().all(q)

      assert pages == [[p2.id], [p3.id], [p1.id]]
    end

    test "page_fragment:duplicate", %{socket: socket} do
      p1 = Factory.insert(:page_fragment, data: [])

      ref = push(socket, "page_fragment:duplicate", %{"id" => p1.id})

      assert_reply ref, :ok, %{
        code: 200,
        page_fragment: %Brando.Pages.PageFragment{key: "header_kopi"}
      }

      ref = push(socket, "page_fragment:duplicate", %{"id" => 9_999_999_999})

      assert_reply ref, :error, %{
        code: 400,
        message: "Fragment not found!"
      }
    end

    test "page_fragment:rerender", %{socket: socket} do
      p1 =
        Factory.insert(:page_fragment,
          data: [
            %{
              "type" => "text",
              "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
            }
          ]
        )

      ref = push(socket, "page_fragment:rerender", %{"id" => to_string(p1.id)})
      assert_reply ref, :ok, %{code: 200}
    end

    test "page_fragment:rerender_all", %{socket: socket} do
      _ =
        Factory.insert(:page_fragment,
          data: [
            %{
              "type" => "text",
              "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
            }
          ]
        )

      ref = push(socket, "page_fragment:rerender_all", %{})
      assert_reply ref, :ok, %{code: 200}
    end
  end

  #
  # USERS
  #

  describe "users" do
    test "user:deactivate", %{socket: socket} do
      u1 = Factory.insert(:random_user)
      ref = push(socket, "user:deactivate", %{"user_id" => u1.id})
      assert_reply ref, :ok, %{code: 200, user_id: user_id}
      assert user_id == u1.id

      {:ok, u2} = Brando.Users.get_user(u1.id)
      assert u2.active == false
    end

    test "user:activate", %{socket: socket} do
      u1 = Factory.insert(:random_user, active: false)
      ref = push(socket, "user:activate", %{"user_id" => u1.id})
      assert_reply ref, :ok, %{code: 200, user_id: user_id}
      assert user_id == u1.id

      {:ok, u2} = Brando.Users.get_user(u1.id)
      assert u2.active == true
    end

    test "user:state", %{socket: socket} do
      _u1 = Factory.insert(:random_user, active: false)
      ref = push(socket, "user:state", %{"active" => true})
      assert_reply ref, :ok
    end
  end

  #
  # DATASOURCES
  #

  describe "datasources" do
    test "datasource:list_modules", %{socket: socket} do
      ref = push(socket, "datasource:list_modules", %{})
      assert_reply ref, :ok, %{code: 200, available_modules: []}
    end

    test "datasource:list_module_keys", %{socket: socket} do
      ref =
        push(socket, "datasource:list_module_keys", %{
          "module" => "Elixir.BrandoIntegration.ModuleWithDatasource"
        })

      assert_reply ref, :ok, %{
        code: 200,
        available_module_keys: %{many: [:all], one: [], selection: [:featured]}
      }
    end

    test "datasource:list_available_entries", %{socket: socket} do
      ref =
        push(socket, "datasource:list_available_entries", %{
          "module" => "Elixir.BrandoIntegration.ModuleWithDatasource",
          "query" => "featured"
        })

      assert_reply ref, :ok, %{
        code: 200,
        available_entries: [%{id: 1, label: "label 1"}, %{id: 2, label: "label 2"}]
      }
    end
  end

  #
  # TEMPLATES
  #

  describe "templates" do
    test "templates:list_templates", %{socket: socket} do
      _ = Factory.insert(:template)
      ref = push(socket, "templates:list_templates", %{})

      assert_reply ref, :ok, %{code: 200, templates: [%{id: _, name: "posts - test"}]}
    end
  end

  #
  # LIVEPREVIEW
  #

  describe "livepreview" do
    test "livepreview:initialize", %{socket: socket} do
      entry = %{"title" => "Page title!"}

      capture_log(fn ->
        ref =
          push(socket, "livepreview:initialize", %{
            "schema" => "Brando.Users.User",
            "entry" => entry,
            "key" => "data",
            "prop" => "page"
          })

        assert_reply ref, :error, %{code: 404}
      end)

      ref =
        push(socket, "livepreview:initialize", %{
          "schema" => "Brando.Pages.Page",
          "entry" => entry,
          "key" => "data",
          "prop" => "page"
        })

      assert_reply ref, :ok, %{code: 200, cache_key: cache_key}

      ref =
        push(socket, "livepreview:render", %{
          "schema" => "Brando.Pages.Page",
          "entry" => entry,
          "key" => "data",
          "prop" => "page",
          "cache_key" => cache_key
        })

      assert_reply ref, :ok, %{code: 200, cache_key: ^cache_key}
    end
  end
end
