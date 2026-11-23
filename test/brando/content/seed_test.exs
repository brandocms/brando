defmodule Brando.Content.SeedTest do
  use Brando.ConnCase, async: false
  use Brando.Test

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Seed
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures

  @jpg Path.expand("../../fixtures/sample.jpg", __DIR__)

  setup do
    user = insert_user()

    module =
      ProposalFixtures.module!(
        user,
        "Teaser",
        ~s(<section class="teaser{% if wide %} wide{% endif %}"><h2>{{ heading }}</h2>{% ref refs.title %}{% ref refs.body %}{% ref refs.cover %}{% ref refs.slot %}{% ref refs.slides %}</section>),
        refs: [
          ProposalFixtures.ref("title", %{type: "header", data: %{text: "Default title", level: 3}}),
          ProposalFixtures.ref("body", %{type: "text", data: %{text: "<p>Default body</p>"}}),
          ProposalFixtures.ref("cover", %{type: "picture", data: %{}}),
          ProposalFixtures.ref("slot", %{
            type: "media",
            data: %{
              available_blocks: ["picture", "video"],
              template_picture: %{title: "Slot picture"},
              template_video: %{}
            }
          }),
          ProposalFixtures.ref("slides", %{type: "gallery", data: %{}})
        ],
        vars: [
          %{type: "string", key: "heading", label: "Heading", value: "Default heading"},
          %{type: "boolean", key: "wide", label: "Wide", value_boolean: false}
        ]
      )

    %{user: user, module: module}
  end

  defp ref(block, name),
    do: block |> Ecto.Changeset.get_assoc(:refs) |> Enum.find(&(Ecto.Changeset.get_field(&1, :name) == name))

  # An MP4's first box is all the upload checks; `brand` "qt  " makes a QuickTime file
  defp video_file!(name, brand \\ "mp42") do
    dir = Path.join(System.tmp_dir!(), "seed-video-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    path = Path.join(dir, name)

    File.write!(
      path,
      <<0, 0, 0, 24, "ftyp", brand::binary, 0, 0, 0, 0, brand::binary, "isom">> <> :binary.copy(<<0>>, 64)
    )

    path
  end

  defp create_page(user, attrs, blocks) do
    params =
      Map.merge(%{title: "Lobby", uri: "lobby", language: "en", template: "default.html", status: :published}, attrs)

    Seed.create_entry(Page, params, user, blocks: blocks)
  end

  describe "upload_image/3" do
    test "stores the file once, with its texts", %{user: user} do
      assert {:ok, image} = Seed.upload_image(@jpg, user, alt: "The lobby", title: "Lobby")
      assert image.alt == %{"en" => "The lobby"}
      assert image.title == %{"en" => "Lobby"}

      # The same bytes again: the library's image, nothing stored
      assert {:ok, again} = Seed.upload_image(@jpg, user)
      assert again.id == image.id
    end

    test "says what is wrong with a file that is not an image", %{user: user} do
      path = Path.join(System.tmp_dir!(), "seed-not-an-image-#{System.unique_integer([:positive])}.jpg")
      File.write!(path, "plain text")
      on_exit(fn -> File.rm(path) end)

      assert {:error, message} = Seed.upload_image(path, user)
      assert is_binary(message)
      assert {:error, _} = Seed.upload_image("no/such/file.jpg", user)
    end
  end

  describe "upload_video/2" do
    test "stores a video file, and refuses another", %{user: user} do
      mp4 = video_file!("intro.mp4")

      assert {:ok, %Brando.Videos.Video{type: :upload} = video} = Seed.upload_video(mp4, user)
      assert video.file_id

      assert {:error, message} = Seed.upload_video(@jpg, user)
      assert message =~ "not a video"
    end

    test "declares a QuickTime file as the type the configuration allows", %{user: user} do
      put_test_env(Brando.Videos,
        default_config: %Brando.Type.VideoConfig{
          upload_strategy: Brando.default_video_upload_strategy(),
          allowed_mimetypes: ["video/quicktime"]
        }
      )

      assert {:ok, %Brando.Videos.Video{type: :upload}} = Seed.upload_video(video_file!("intro.mov", "qt  "), user)
    end
  end

  describe "block/3" do
    test "sets text, header fields, vars and switches a ref off", %{user: user, module: module} do
      block =
        Seed.block(module, user,
          refs: %{"title" => %{text: "Lobby", level: 2}, "body" => "<p>Open from eight.</p>", "slides" => false},
          vars: %{"heading" => "Welcome", "wide" => true}
        )

      html = render_block(Ecto.Changeset.apply_changes(block))
      assert html =~ ~s(<section class="teaser wide"><h2>Welcome</h2>)
      assert html =~ "<h2>Lobby</h2>"
      assert html =~ "<p>Open from eight.</p>"
      assert html =~ "<!-- !a[slides] -->"
      assert Ecto.Changeset.get_field(block, :creator_id) == user.id
    end

    test "takes an image or a path for a picture ref, and retypes a media ref", %{user: user, module: module} do
      {:ok, image} = Seed.upload_image(@jpg, user)
      block = Seed.block(module, user, refs: %{"cover" => image, "slot" => @jpg})

      assert Ecto.Changeset.get_field(ref(block, "cover"), :image_id) == image.id

      slot = ref(block, "slot")
      assert Ecto.Changeset.get_field(slot, :image_id) == image.id
      assert %{type: "picture", data: %{title: "Slot picture"}} = Ecto.Changeset.get_field(slot, :data)

      html = render_block(Ecto.Changeset.apply_changes(block))
      assert html =~ "<img"
      # The template's caption, shown with the slot's picture
      assert html =~ "Slot picture"
    end

    test "makes a gallery of images and paths", %{user: user, module: module} do
      {:ok, image} = Seed.upload_image(@jpg, user)
      {:ok, page} = create_page(user, %{}, [Seed.block(module, user, refs: %{"slides" => [image, @jpg]})])

      [%{block: block}] =
        Brando.Repo.preload(page, entry_blocks: [block: [refs: [gallery: :gallery_objects]]]).entry_blocks

      slides = Enum.find(block.refs, &(&1.name == "slides"))
      assert [%{image_id: id, sequence: 0}, %{image_id: id, sequence: 1}] = slides.gallery.gallery_objects
      assert id == image.id
      assert slides.gallery.config_target == "ref:gallery"
    end

    test "finds the module by uid and names what it does not have", %{user: user, module: module} do
      block = Seed.block(module.uid, user)
      assert Ecto.Changeset.get_field(block, :module_id) == module.id

      assert_raise ArgumentError, ~r/no module with the uid "nope"/, fn -> Seed.block("nope", user) end

      error = assert_raise ArgumentError, fn -> Seed.block(module, user, vars: %{"title" => "x"}) end
      assert error.message =~ ~s(no var "title")
      assert error.message =~ ~s(["heading", "wide"])

      assert_raise ArgumentError, ~r/no ref "image"/, fn -> Seed.block(module, user, refs: %{"image" => @jpg}) end

      assert_raise ArgumentError, ~r/a gallery ref takes a list/, fn ->
        Seed.block(module, user, refs: %{"slides" => @jpg})
      end

      assert_raise ArgumentError, ~r/could not upload no\/such\.jpg/, fn ->
        Seed.block(module, user, refs: %{"cover" => "no/such.jpg"})
      end
    end

    test "refuses media of a kind the ref does not take, naming what it takes", %{user: user, module: module} do
      {:ok, image} = Seed.upload_image(@jpg, user)
      {:ok, video} = Seed.upload_video(video_file!("intro.mp4"), user)

      assert_raise ArgumentError, ~r/the ref "cover" takes an image/, fn ->
        Seed.block(module, user, refs: %{"cover" => video})
      end

      assert_raise ArgumentError, ~r/the ref "cover" takes an image/, fn ->
        Seed.block(module, user, refs: %{"cover" => video_file!("clip.mp4")})
      end

      assert_raise ArgumentError, ~r/the ref "slides" takes a gallery/, fn ->
        Seed.block(module, user, refs: %{"slides" => image})
      end
    end

    test "refuses a type a media ref's module author left out", %{user: user} do
      {:ok, video} = Seed.upload_video(video_file!("intro.mp4"), user)

      module =
        ProposalFixtures.module!(user, "Picture slot", ~s({% ref refs.slot %}),
          refs: [ProposalFixtures.ref("slot", %{type: "media", data: %{available_blocks: ["picture"]}})]
        )

      assert_raise ArgumentError, ~r/the ref "slot" takes an image/, fn ->
        Seed.block(module, user, refs: %{"slot" => video})
      end
    end

    test "refuses a string for a ref that holds no text", %{user: user} do
      module =
        ProposalFixtures.module!(user, "Markup", ~s({% ref refs.embed %}{% ref refs.logo %}),
          refs: [
            ProposalFixtures.ref("embed", %{type: "html", data: %{text: "<div></div>"}}),
            ProposalFixtures.ref("logo", %{type: "svg", data: %{code: "<svg></svg>"}})
          ]
        )

      for name <- ["embed", "logo"] do
        assert_raise ArgumentError, ~r/the ref "#{name}" holds no text.*map/, fn ->
          Seed.block(module, user, refs: %{name => "<p>Hi</p>"})
        end
      end
    end

    test "sets an HTML or SVG ref's markup for a superuser only", %{user: user} do
      module =
        ProposalFixtures.module!(user, "Markup", ~s({% ref refs.embed %}{% ref refs.logo %}),
          refs: [
            ProposalFixtures.ref("embed", %{type: "html", data: %{text: "<div></div>"}}),
            ProposalFixtures.ref("logo", %{type: "svg", data: %{code: "<svg></svg>"}})
          ]
        )

      admin = insert_user(role: :admin)

      assert_raise ArgumentError, ~r/the ref "embed".*superuser/, fn ->
        Seed.block(module, admin, refs: %{"embed" => %{text: "<script></script>"}})
      end

      assert_raise ArgumentError, ~r/the ref "logo".*superuser/, fn ->
        Seed.block(module, admin, refs: %{"logo" => %{code: "<svg onload=x></svg>"}})
      end

      block = Seed.block(module, user, refs: %{"embed" => %{text: "<b>Hi</b>"}})
      assert %{data: %{text: "<b>Hi</b>"}} = Ecto.Changeset.get_field(ref(block, "embed"), :data)
    end
  end

  describe "create_entry/4" do
    test "creates a rendered entry through its context, with an identifier and a revision", %{user: user, module: module} do
      assert {:ok, page} = create_page(user, %{}, [Seed.block(module, user, vars: %{"heading" => "Lobby"})])

      assert page.language == :en
      assert page.creator_id == user.id
      assert page.rendered_blocks =~ "<h2>Lobby</h2>"
      assert {:ok, _identifier} = Brando.Content.get_identifier(Page, %{id: page.id})
      assert {:ok, _active} = Brando.Revisions.get_active_revision(Page, page.id)

      # As the site reads it, from the cache
      assert {:ok, cached} = Brando.Pages.get_page(%{matches: %{uri: "lobby", language: "en"}, cache: {:ttl, :infinite}})
      assert cached.rendered_blocks =~ "<h2>Lobby</h2>"
    end

    test "takes blocks by field and an atom language", %{user: user, module: module} do
      assert {:ok, page} = create_page(user, %{language: :en}, blocks: [Seed.block(module, user)])
      assert page.rendered_blocks =~ "Default heading"

      assert_raise ArgumentError, ~r/has no block field :footer/, fn ->
        create_page(user, %{uri: "other"}, footer: [Seed.block(module, user)])
      end
    end

    test "is refused without the right to create the entry", %{module: module} do
      user = insert_user(role: :user)
      assert {:error, :forbidden} = create_page(user, %{}, [Seed.block(module, user)])
    end

    test "returns the changeset of invalid params", %{user: user} do
      assert {:error, %Ecto.Changeset{valid?: false}} = Seed.create_entry(Page, %{title: "No uri"}, user)
    end
  end

  test "add_blocks/4 adds blocks after the entry's or at a position", %{user: user, module: module} do
    {:ok, page} = create_page(user, %{}, [Seed.block(module, user, vars: %{"heading" => "First"})])

    {:ok, page} = Seed.add_blocks(page, [Seed.block(module, user, vars: %{"heading" => "Last"})], user)
    {:ok, page} = Seed.add_blocks(page, [Seed.block(module, user, vars: %{"heading" => "Between"})], user, at: 1)

    assert page.rendered_blocks =~ ~r/First.*Between.*Last/s

    sequences =
      Brando.Repo.all(from(j in Page.Blocks, where: j.entry_id == ^page.id, order_by: j.sequence, select: j.sequence))

    assert sequences == [0, 1, 2]
  end

  test "add_blocks/4 refuses an entry in the trash", %{user: user, module: module} do
    {:ok, page} = create_page(user, %{}, [])
    {:ok, _} = Brando.Pages.delete_page(page, user)

    assert_raise ArgumentError, ~r/trash/, fn ->
      Seed.add_blocks(page, [Seed.block(module, user)], user)
    end

    assert Brando.Repo.all(from(j in Page.Blocks, where: j.entry_id == ^page.id)) == []
  end

  test "menu_item/3 links to a URL or to an entry through its identifier", %{user: user} do
    {:ok, page} = create_page(user, %{}, [])

    {:ok, menu} =
      Brando.Navigation.create_menu(
        %{
          title: "Main menu",
          key: "main",
          language: "en",
          status: :published,
          items: [Seed.menu_item("Home", "/"), Seed.menu_item(nil, page, key: "lobby", new_tab: true)]
        },
        user
      )

    menu = Brando.Repo.preload(menu, items: :link)
    [home, lobby] = Enum.sort_by(menu.items, & &1.sequence)

    assert %{key: "home", link: %{link_type: :url, value: "/", link_text: "Home"}} = home
    assert lobby.key == "lobby"
    {:ok, identifier} = Brando.Content.get_identifier(Page, %{id: page.id})
    assert %{link_type: :identifier, identifier_id: identifier_id, link_target_blank: true} = lobby.link
    assert identifier_id == identifier.id

    # A delete function takes the struct as well as the id
    assert {:ok, _} = Brando.Navigation.delete_item(lobby, user)
    assert {:ok, _} = Brando.Navigation.delete_menu(menu, user)
  end

  test "menu_item/3 leaves the key to follow the link, as the admin does", %{user: user} do
    {:ok, page} = create_page(user, %{title: "The Lobby"}, [])
    refute Map.has_key?(Seed.menu_item("About us", "/about"), :key)

    {:ok, menu} =
      Brando.Navigation.create_menu(
        %{
          title: "Main menu",
          key: "main",
          language: "en",
          status: :published,
          items: [Seed.menu_item("About us", "/about"), Seed.menu_item(nil, page)]
        },
        user
      )

    keys = menu |> Brando.Repo.preload(:items) |> Map.fetch!(:items) |> Enum.sort_by(& &1.sequence) |> Enum.map(& &1.key)
    assert keys == ["about_us", "the_lobby"]
  end

  test "put_globals/4 sets a global set's values by key", %{user: user} do
    {:ok, _set} =
      Brando.Sites.create_global_set(
        %{
          label: "Contact",
          key: "contact",
          language: "en",
          vars: [
            %{type: "string", key: "email", label: "Email", value: "old@acme.test"},
            %{type: "boolean", key: "open", label: "Open", value_boolean: false}
          ]
        },
        user
      )

    assert {:ok, set} = Seed.put_globals("contact", :en, %{"email" => "hi@acme.test", "open" => true}, user)
    assert %{"email" => "hi@acme.test", "open" => true} = Map.new(set.vars, &{&1.key, &1.value || &1.value_boolean})

    assert {:error, :not_found} = Seed.put_globals("contact", "no", %{}, user)

    assert_raise ArgumentError, ~r/the global set has no var "phone"/, fn ->
      Seed.put_globals("contact", "en", %{"phone" => "1"}, user)
    end
  end

  test "render/1 renders the entry again, as its module renders now", %{user: user, module: module} do
    {:ok, page} = create_page(user, %{}, [Seed.block(module, user)])
    Brando.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [rendered_blocks: "stale"])

    assert {:ok, page} = Seed.render(page)
    assert page.rendered_blocks =~ "Default heading"
  end

  test "a generated delete function takes the entry or its id", %{user: user} do
    {:ok, first} = create_page(user, %{uri: "first"}, [])
    {:ok, second} = create_page(user, %{uri: "second"}, [])

    assert {:ok, _} = Brando.Pages.delete_page(first, user)
    assert {:ok, _} = Brando.Pages.delete_page(second.id, user)
  end

  describe "on a multi-site install" do
    defmodule Migrator do
      @behaviour Brando.Environments.Migrator

      @impl true
      def migrate(_site, _environment), do: {:ok, []}
    end

    @prefix "tenant_acme_production"

    setup %{user: user} do
      root = Path.join(System.tmp_dir!(), "brando-seed-#{System.unique_integer([:positive])}")
      put_test_env(:media_path, Path.join(root, "media"))
      put_test_env(:sites_path, Path.join(root, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi, global: true)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()

      on_exit(fn ->
        File.rm_rf(root)
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
        Brando.TenantCaches.clear([@prefix])
      end)

      {:ok, _site} =
        Brando.Tenant.Setup.create_site(
          %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
          user,
          environments: [
            %{name: "Production", key: "production", live: true, domain: "acme.test"},
            %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"}
          ]
        )

      :ok
    end

    test "creates the content in the environment it runs in", %{user: user} do
      page =
        Brando.Tenant.with_prefix(Brando.Tenant.prefix("acme", "production"), fn ->
          module =
            ProposalFixtures.module!(user, "Image row", ~s(<figure>{% ref refs.picture %}</figure>),
              refs: [ProposalFixtures.ref("picture", %{type: "picture", data: %{}})]
            )

          {:ok, page} = create_page(user, %{uri: "acme-lobby"}, [Seed.block(module, user, refs: %{"picture" => @jpg})])
          assert page.rendered_blocks =~ "<img"
          assert Brando.Repo.get(Page, page.id)
          page
        end)

      refute Brando.Repo.one(from(p in Page, where: p.uri == "acme-lobby"), prefix: "public")
      assert Brando.Repo.get(Page, page.id, prefix: @prefix)
      assert Brando.Repo.one(from(i in Brando.Images.Image, select: count()), prefix: @prefix) == 1
    end

    # Gives the row `id` of `schema` in `prefix` the id `new_id`
    defp renumber!(schema, prefix, id, new_id) do
      {1, _} = Brando.Repo.update_all(from(r in schema, where: r.id == ^id), [set: [id: new_id]], prefix: prefix)
      new_id
    end

    test "a delete function refuses an entry of another environment", %{user: user} do
      staging = Brando.Tenant.prefix("acme", "staging")

      {page, menu} =
        Brando.Tenant.with_prefix(staging, fn ->
          {:ok, page} = create_page(user, %{uri: "staged"}, [])

          {:ok, menu} =
            Brando.Navigation.create_menu(%{title: "Menu", key: "main", language: "en", status: :published}, user)

          {page, menu}
        end)

      Brando.Tenant.with_prefix(@prefix, fn ->
        {:ok, live_page} = create_page(user, %{uri: "live"}, [])

        {:ok, live_menu} =
          Brando.Navigation.create_menu(%{title: "Menu", key: "main", language: "en", status: :published}, user)

        renumber!(Page, @prefix, live_page.id, page.id)
        renumber!(Brando.Navigation.Menu, @prefix, live_menu.id, menu.id)

        assert_raise ArgumentError, ~r/environment/, fn -> Brando.Pages.delete_page(page, user) end
        assert_raise ArgumentError, ~r/environment/, fn -> Brando.Navigation.delete_menu(menu, user) end

        assert %{deleted_at: nil} = Brando.Repo.get(Page, page.id)
        assert Brando.Repo.get(Brando.Navigation.Menu, menu.id)
      end)
    end

    # A user's id names the same row from every environment
    test "an entry of a schema every environment shares belongs to each of them", %{user: user} do
      Brando.Tenant.with_prefix(@prefix, fn ->
        assert Brando.Tenant.ensure_current!(user) == :ok
        assert Brando.Tenant.ensure_current!(%Brando.Users.User{id: user.id}) == :ok
      end)
    end

    test "builds a block of a shared module, not of a local module with its id", %{user: user} do
      {:ok, shared} =
        Brando.Content.SharedLibrary.create_shared(
          :module,
          %{
            name: %{"en" => "Shared"},
            namespace: %{"en" => "general"},
            help_text: %{"en" => "Help"},
            class: "shared",
            code: ~s({% ref refs.body %}),
            refs: [ProposalFixtures.ref("body", %{type: "text", data: %{}})]
          },
          user
        )

      Brando.Tenant.with_prefix(@prefix, fn ->
        # A local module without refs, with the shared module's id
        local = ProposalFixtures.module!(user, "Local", "<p>Local</p>", [])
        id = renumber!(Brando.Content.Module, @prefix, local.id, shared.id)
        assert %{library_origin: :local, refs: []} = Brando.Content.fetch_module(id, :local)

        shared = Brando.Content.SharedLibrary.get_for_current_tenant(:module, id, :shared)
        assert %{library_origin: :shared, refs: [%{name: "body"}]} = shared

        block = Seed.block(shared, user)
        assert Ecto.Changeset.get_field(block, :module_origin) == :shared
        assert [ref] = Ecto.Changeset.get_assoc(block, :refs)
        assert Ecto.Changeset.get_field(ref, :name) == "body"
      end)
    end
  end
end
