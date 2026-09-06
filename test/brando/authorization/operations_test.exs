defmodule Brando.Authorization.OperationsTest do
  use Brando.ConnCase
  alias Brando.Authorization.{Boundary, Catalog, Groups, Media, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    {:ok, _} = Migration.run()
    page = Factory.insert(:page, status: :draft)
    %{owner: owner, editor: editor, user: user, page: page, scope: Scope.standalone(owner)}
  end

  test "status events recheck publication rights and reject unregistered schemas", c do
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.update"])
    assert {:error, :forbidden} = Brando.Trait.Status.update_status(Page, c.page.id, "published", c.user)

    assert {:error, :forbidden} =
             Brando.Trait.Status.update_status("Unregistered.Resource", c.page.id, "published", c.owner)

    assert Repo.get!(Page, c.page.id).status == :draft
    assert {:ok, published} = Brando.Trait.Status.update_status(Page, c.page.id, "published", c.editor)
    assert published.status == :published
  end

  test "the legacy tuple adapter follows group authority after cutover", c do
    assert {:error, :unauthorized} =
             BrandoIntegration.Authorization.Can.can?(%{c.user | role: :superuser}, :update, c.page)

    assert {:ok, :authorized} = BrandoIntegration.Authorization.Can.can?(c.owner, :update, c.page)
  end

  test "duplication requires create permission as well as source access", c do
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.duplicate"])
    count = Repo.aggregate(Page, :count)
    assert {:error, :forbidden} = Pages.duplicate_page(c.page.id, c.user)
    assert Repo.aggregate(Page, :count) == count
  end

  test "bulk reorder is authorized atomically, including published rows", c do
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.reorder"])
    published = Factory.insert(:page, status: :published)
    before = Repo.get!(Page, c.page.id).sequence
    assert {:error, :forbidden} = Brando.Trait.Sequenced.sequence(Page, %{"ids" => [published.id, c.page.id]}, c.user)
    assert Repo.get!(Page, c.page.id).sequence == before
    assert {:error, :forbidden} = Brando.Trait.Sequenced.sequence(Page, %{"ids" => [c.page.id, -1]}, c.user)
  end

  test "restoring deleted live content requires publication rights", c do
    grant(c, ["brando.admin.access", "brando.pages.read", "brando.pages.update", "brando.pages.restore"])

    deleted =
      Repo.update!(
        Ecto.Changeset.change(c.page, status: :published, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      )

    assert {:error, :forbidden} = Boundary.restore(c.user, deleted)
    assert Repo.get!(Page, c.page.id).deleted_at
  end

  test "profile access cannot disable an account or change its legacy role", c do
    assert {:ok, renamed} = Brando.Users.update_user(c.editor.id, %{name: "My updated name"}, c.editor)
    assert renamed.name == "My updated name"
    assert {:error, :forbidden} = Brando.Users.update_user(c.editor.id, %{active: false}, c.editor)
    assert {:error, {:user, :not_found}} = Brando.Users.update_user(c.user.id, %{name: "Someone else"}, c.editor)
    assert Repo.get!(Brando.Users.User, c.editor.id).active
  end

  test "upload intake fails before transfer for users without media creation", c do
    meta = %{name: "story.pdf", size: 100, type: "application/pdf"}
    assert {:error, _} = Brando.Uploads.initiate(:file, "default", meta, c.user)
    assert {:ok, :server} = Brando.Uploads.initiate(:file, "default", meta, c.editor)
    assert {:error, _} = Media.authorize(nil, :file)
  end

  test "signed upload scopes cannot be replayed by another user or after revocation", c do
    token = Media.token(c.editor)
    target = %{"scope_token" => token}
    assert :accepted = Media.with_intent(target, c.editor, fn -> :accepted end)
    assert {:error, _} = Media.with_intent(target, c.owner, fn -> flunk("replayed scope") end)
    Repo.update!(Ecto.Changeset.change(c.editor, active: false))
    assert {:error, _} = Media.with_intent(target, c.editor, fn -> flunk("stale access") end)
    assert Boundary.current_scope() == nil
  end

  test "internal schemas and media processing statuses are absent from the permission catalog" do
    assert Catalog.get(:create, Brando.Revisions.Revision) == nil
    assert Catalog.get(:publish, Brando.Images.Image) == nil
    assert Catalog.get(:publish, Page)
  end

  test "identifier searches honor source permissions before returning metadata", c do
    {:ok, _} = Brando.Content.create_identifier(Page, c.page)

    Boundary.with_scope(Scope.standalone(c.user), fn ->
      assert {:ok, []} = Brando.Content.list_identifiers(Page, %{})
      assert {:ok, []} = Brando.Content.list_identifiers(%{})
    end)

    grant(c, ["brando.admin.access", "brando.pages.read"])

    Boundary.with_scope(Scope.standalone(c.user), fn ->
      assert {:ok, [identifier]} = Brando.Content.list_identifiers(Page, %{})
      assert identifier.entry_id == c.page.id
    end)
  end

  test "a missing publishing actor never becomes a trusted system actor", c do
    job = %Oban.Job{args: %{"schema" => to_string(Page), "id" => c.page.id, "status" => "published", "user_id" => -1}}
    assert {:error, :forbidden} = Brando.Worker.EntryPublisher.perform(job)
    assert Repo.get!(Page, c.page.id).status == :draft
  end

  test "revision metadata and scheduling cannot bypass resource permissions", c do
    {:ok, revision} = Brando.Revisions.create_revision(c.page, :system, false)
    grant(c, ["brando.admin.access", "brando.pages.read"])

    Boundary.with_scope(Scope.standalone(c.user), fn ->
      assert {0, _} = Brando.Revisions.protect_revision(Page, c.page.id, revision.revision, true)
      assert {0, _} = Brando.Revisions.describe_revision(Page, c.page.id, revision.revision, "Unauthorized")
      assert {0, _} = Brando.Revisions.delete_revision(Page, c.page.id, revision.revision)
      assert {:error, :forbidden} = Brando.Publisher.cancel_scheduled_revision(Page, c.page.id, revision.revision)
    end)

    assert Repo.get_by!(Brando.Revisions.Revision,
             entry_id: c.page.id,
             entry_type: to_string(Page),
             revision: revision.revision
           ).description == nil
  end

  test "image editing is rejected before replacing the source bytes", c do
    image = Factory.insert(:image)
    grant(c, ["brando.admin.access", "brando.images.read"])
    assert {:error, :forbidden} = Brando.Images.Crop.save_replace(image, "not an image", %{x: 50, y: 50}, c.user)
    assert {:error, :forbidden} = Brando.Images.Crop.save_as_new_copy(image, "not an image", %{x: 50, y: 50}, c.user)
    assert Repo.get!(Brando.Images.Image, image.id).path == image.path
  end

  test "shared library writes and installation lifecycle do not accept a content editor", c do
    Boundary.with_scope(Scope.standalone(c.editor), fn ->
      assert {:error, :forbidden} = Brando.Content.SharedLibrary.create_shared(:module, %{name: "Forged"}, c.editor)
      assert {:error, :forbidden} = Brando.Tenant.Setup.suspend_site(%Brando.Sites.Site{id: -1, key: "missing"})
      assert {:error, :forbidden} = Brando.Tenant.Setup.delete_site(%Brando.Sites.Site{id: -1, key: "missing"})
    end)
  end

  test "operator recovery is audited and cannot revive a disabled account", c do
    assert {:ok, :ok} = Migration.recover_superuser(c.user)
    assert Brando.Authorization.Engine.superuser?(Scope.installation(c.user))

    assert Repo.exists?(
             from(e in Brando.Authorization.AuditEvent,
               where: e.action == "operator.superuser_recovered" and e.subject_user_id == ^c.user.id
             )
           )

    Repo.update!(Ecto.Changeset.change(c.user, active: false))
    assert {:error, :inactive_account} = Migration.recover_superuser(c.user)
  end

  defp grant(c, keys) do
    {:ok, group} = Groups.create(c.scope, %{name: "Specific operations"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    group
  end
end
