defmodule Brando.Test.FactoryTest do
  use Brando.ConnCase, async: false
  use Brando.Test

  alias Brando.Pages.Page
  alias Brando.SyncTest.{Article, ArticleItem}

  defmodule RequiredAssets do
    use Brando.Blueprint,
      application: "Brando",
      domain: "FactoryTest",
      schema: "RequiredAssets",
      singular: "required_asset",
      plural: "required_assets",
      gettext_module: Brando.Gettext

    assets do
      asset :cover, :image, required: true, cfg: :default
      asset :clip, :video, required: true, cfg: :default
      asset :pdf, :file, required: true, cfg: :default
    end
  end

  test "derives params from the blueprint's required attributes" do
    params = params_for(Article)

    assert params.title =~ "Title"
    assert params.slug =~ ~r/^slug-\d+$/
    assert params.status == :published
    assert params.language == Brando.config(:default_language)
    refute Map.has_key?(params, :subtitle)

    # Unique per call, for unique fields.
    refute params_for(Article).slug == params.slug
  end

  test "the blueprint's factory and the given attrs come first" do
    params = params_for(Page, title: "Given")
    assert params.title == "Given"
    assert params.template == "default.html"
  end

  test "builds a valid entry without inserting it" do
    article = build_entry(Article, %{title: "Built", year: 2024})
    assert %Article{id: nil, title: "Built", year: 2024, status: :published} = article
    assert Brando.Repo.aggregate(Article, :count) == 0
  end

  test "inserts through the context, as the admin creates entries" do
    user = insert_user()
    article = insert_entry(Article, %{title: "Inserted"}, user: user)

    assert %Article{id: id, title: "Inserted", creator_id: creator_id} = article
    assert id
    assert creator_id == user.id
    assert {:ok, %{title: "Inserted"}} = Brando.SyncTest.get_article(id)
  end

  test "says what is missing when the entry is not valid" do
    error = assert_raise ArgumentError, fn -> insert_entry(Article, %{title: nil}) end
    assert error.message =~ "Brando.SyncTest.Article is not valid"
    assert error.message =~ "title"
  end

  test "refuses a schema that is not a blueprint" do
    assert_raise ArgumentError, ~r/not a blueprint/, fn -> params_for(Brando.Users.UserToken) end
  end

  describe "in a tenant's schema" do
    @prefix "tenant_factory-test_preview"

    setup do
      put_test_env(:tenancy_mode, :multi)
      repo = Brando.Repo.repo()
      repo.query!(~s(CREATE SCHEMA "#{@prefix}"))

      for table <- ~w(images videos files synctest_article_items) do
        repo.query!(~s|CREATE TABLE "#{@prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
      end

      %{user: insert_user()}
    end

    test "required assets' default records are inserted in the tenant's schema", %{user: user} do
      Brando.Tenant.with_prefix(@prefix, fn ->
        params = params_for(RequiredAssets, %{}, user: user)

        for {schema, id} <- [
              {Brando.Images.Image, params.cover_id},
              {Brando.Videos.Video, params.clip_id},
              {Brando.Files.File, params.pdf_id}
            ] do
          assert Brando.Repo.get(schema, id)
          refute Brando.Repo.get(schema, id, prefix: "public")
        end
      end)
    end

    test "an entry without a create function is inserted in the tenant's schema", %{user: user} do
      Brando.Tenant.with_prefix(@prefix, fn ->
        item = insert_entry(ArticleItem, %{label: "Tenant"}, user: user)

        assert item.__meta__.prefix == @prefix
        assert %ArticleItem{label: "Tenant"} = Brando.Repo.get(ArticleItem, item.id)
        refute Brando.Repo.get(ArticleItem, item.id, prefix: "public")
      end)
    end
  end
end
