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

      assert_raise ArgumentError, ~r/could not upload no\/such\.jpg/, fn ->
        Seed.block(module, user, refs: %{"cover" => "no/such.jpg"})
      end
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
    {:ok, identifier} = Brando.Content.get_identifier(Page, %{id: page.id})
    assert %{link_type: :identifier, identifier_id: identifier_id, link_target_blank: true} = lobby.link
    assert identifier_id == identifier.id

    # A delete function takes the struct as well as the id
    assert {:ok, _} = Brando.Navigation.delete_item(lobby, user)
    assert {:ok, _} = Brando.Navigation.delete_menu(menu, user)
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
          environments: [%{name: "Production", key: "production", live: true, domain: "acme.test"}]
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
  end
end
