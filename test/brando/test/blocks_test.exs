defmodule Brando.Test.BlocksTest do
  use Brando.ConnCase, async: false
  use Brando.Test

  alias Brando.Pages.Page

  setup do
    user = insert_user()

    module =
      Brando.ProposalFixtures.module!(
        user,
        "Teaser",
        ~s(<section class="teaser{% if wide %} wide{% endif %}"><h2>{{ heading }}</h2>{% ref refs.body %}{% ref refs.cover %}</section>),
        refs: [
          Brando.ProposalFixtures.ref("body", %{type: "text", data: %{text: "<p>Default body</p>"}}),
          Brando.ProposalFixtures.ref("cover", %{type: "picture", data: %{}})
        ],
        vars: [
          %{type: "string", key: "heading", label: "Heading", value: "Default heading"},
          %{type: "boolean", key: "wide", label: "Wide", value_boolean: false}
        ]
      )

    %{user: user, module: module}
  end

  test "renders a module with its defaults", %{module: module} do
    html = render_block(module)
    assert html =~ ~s(<section class="teaser"><h2>Default heading</h2>)
    assert html =~ "<p>Default body</p>"
  end

  test "renders a module with vars and refs given", %{module: module} do
    html = render_block(module, vars: %{"heading" => "Lobby", "wide" => true}, refs: %{"body" => %{text: "<p>Hi</p>"}})
    assert html =~ ~s(<section class="teaser wide"><h2>Lobby</h2><div class="paragraph"><p>Hi</p></div>)
    refute html =~ "Default"
  end

  test "renders a block, with the entry in the template", %{module: module, user: user} do
    module = %{module | code: "<h1>{{ entry.title }}</h1>{% ref refs.body %}"}
    {:ok, module} = Brando.Content.update_module(module.id, %{code: module.code}, user)
    block = build_block(module, refs: %{"body" => false})

    # A ref switched off leaves a marker, as on the site.
    assert render_block(block, entry: %Page{title: "Identity"}) == "<h1>Identity</h1><!-- !a[body] -->"
  end

  test "names the vars and refs a module has when given others", %{module: module} do
    error = assert_raise ArgumentError, fn -> render_block(module, vars: %{"title" => "x"}) end
    assert error.message =~ ~s(no var "title")
    assert error.message =~ ~s(["heading", "wide"])

    assert_raise ArgumentError, ~r/no ref "image"/, fn -> render_block(module, refs: %{"image" => %{}}) end
  end

  test "adds a block to an entry and renders the entry", %{module: module, user: user} do
    page = insert_entry(Page, %{title: "Identity"}, user: user)
    block = insert_block(page, module, vars: %{"heading" => "Added"}, user: user)

    assert block.id
    page = Brando.Repo.get!(Page, page.id)
    assert page.rendered_blocks =~ "<h2>Added</h2>"
  end

  test "an entry can be inserted with blocks", %{module: module, user: user} do
    page = insert_entry(Page, %{}, user: user, blocks: [module, {module, vars: %{"heading" => "Second"}}])

    assert page.rendered_blocks =~ ~r/Default heading.*Second/s
    assert length(page.entry_blocks) == 2
  end

  describe "in a tenant's schema" do
    @prefix "tenant_blocks-test_preview"

    setup do
      put_test_env(:tenancy_mode, :multi)
      repo = Brando.Repo.repo()
      repo.query!(~s(CREATE SCHEMA "#{@prefix}"))

      for table <-
            ~w(content_modules content_blocks content_refs content_vars content_table_rows content_block_identifiers content_containers sites_identities pages pages_blocks pages_alternates pages_fragments content_palettes sites_global_sets) do
        repo.query!(~s|CREATE TABLE "#{@prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
      end

      :ok
    end

    test "adds the block and its join row in the tenant's schema", %{user: user} do
      # A public page with the tenant page's id: a join row written to public
      # would land on it without a foreign key error.
      public_page =
        Brando.Repo.insert!(%Page{
          title: "Public page",
          uri: "public-page",
          language: :en,
          template: "default.html",
          creator_id: user.id
        })

      Brando.Tenant.with_prefix(@prefix, fn ->
        module =
          Brando.Repo.insert!(%Brando.Content.Module{
            uid: Brando.Utils.generate_uid(),
            name: %{"en" => "Tenant teaser"},
            namespace: %{"en" => "Content"},
            help_text: %{"en" => "Help"},
            class: "tenant-teaser",
            code: "<h2>Tenant</h2>"
          })

        page =
          Brando.Repo.insert!(%Page{
            id: public_page.id,
            title: "Tenant page",
            uri: "tenant-page",
            language: :en,
            template: "default.html",
            creator_id: user.id
          })

        first = insert_block(page, module, user: user)
        second = insert_block(page, module, user: user)

        assert Brando.Repo.get(Brando.Content.Block, first.id)
        refute Brando.Repo.get(Brando.Content.Block, first.id, prefix: "public")

        # The sequence counts the blocks the entry has in the tenant's schema.
        joins = from(j in Page.Blocks, where: j.entry_id == ^page.id, order_by: j.sequence)
        assert Brando.Repo.all(from(j in joins, select: {j.block_id, j.sequence})) == [{first.id, 0}, {second.id, 1}]
        assert Brando.Repo.aggregate(joins, :count, prefix: "public") == 0
        assert Brando.Repo.get!(Page, page.id).rendered_blocks =~ "<h2>Tenant</h2>"
      end)
    end
  end
end
