defmodule Brando.Content.TransferLockedFieldsTest do
  # A bundle sets no field a form locks for anyone but a superuser
  # (`LockedFields`), in either authorization mode: an image's `path`, which
  # the crop editor writes to, stays what the upload made it, on an existing
  # image and on a new one. Everything else in the bundle still imports.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.Archive
  alias Brando.Factory
  alias Brando.Images.Crop
  alias Brando.Images.Image
  alias Brando.Tenant.Storage
  alias Brando.Test.Users
  alias BrandoAdmin.Components.Form.LockedFields

  @repointed "images/transfer-locked/repointed.html"

  # What exporting and importing images takes
  @group ~w(brando.admin.access brando.utilities.read brando.utilities.update brando.images.create
            brando.images.read brando.images.update brando.images.export)

  defp user(:editor, :legacy), do: Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})

  defp user(:editor, :groups) do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    scope = Scope.standalone(Repo.one!(from u in Brando.Users.User, where: u.role == :superuser, limit: 1))
    {:ok, group} = Groups.create(scope, %{name: "Image editors"}, @group)
    {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
    user
  end

  defp put_mode(:legacy), do: %{superuser: Users.insert_user(role: :superuser)}

  defp put_mode(:groups) do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    superuser = Users.insert_user(role: :superuser)
    {:ok, _} = Migration.run()
    %{superuser: superuser}
  end

  defp image(attrs \\ []) do
    Factory.insert(
      :image,
      [path: "images/transfer-locked/own.jpg", width: 100, height: 50, title: "Saved", status: :processed] ++ attrs
    )
  end

  # A bundle of `image`, its attributes hand-edited
  defp bundle(image, user, attributes) do
    assert {:ok, exported} = Transfer.export([%{schema: Image, id: image.id}], user, media: false)
    edited = update_in(exported.bundle, ["entries", Access.at(0), "data", "attributes"], &Map.merge(&1, attributes))
    assert {:ok, binary} = Archive.export(edited, exported.files)
    assert {:ok, archive} = Transfer.read(binary)
    {archive, hd(edited["entries"])["key"]}
  end

  defp import_bundle(archive, targets, user) do
    assert {:ok, plan} = Transfer.preview(archive, targets, user, dependencies: %{})
    assert plan.problems == [], inspect(plan.problems)
    assert {:ok, receipt} = Transfer.apply(plan, user)
    receipt
  end

  for mode <- [:legacy, :groups] do
    describe "#{mode}:" do
      setup do
        put_mode(unquote(mode))
      end

      test "an update keeps a non-superuser's locked fields and takes the rest" do
        user = user(:editor, unquote(mode))
        image = image()

        {archive, key} =
          bundle(image, user, %{
            "path" => @repointed,
            "width" => 999,
            "config_target" => "image:forged",
            "cdn" => true,
            "title" => "Imported"
          })

        import_bundle(archive, %{key => %{"mode" => "update", "id" => image.id}}, user)

        saved = Repo.get!(Image, image.id)

        assert {saved.path, saved.width, saved.config_target, saved.cdn} ==
                 {image.path, 100, image.config_target, image.cdn}

        assert saved.title == %{"en" => "Imported"}
      end

      test "a new image can't be given a path by a non-superuser" do
        user = user(:editor, unquote(mode))
        {archive, key} = bundle(image(), user, %{"path" => @repointed})

        target = %{"mode" => "create", "publication" => "source"}
        assert {:ok, plan} = Transfer.preview(archive, %{key => target}, user, dependencies: %{})
        assert [problem] = plan.problems
        assert problem =~ "path"
        refute Repo.get_by(Image, path: @repointed)
      end

      test "a superuser's bundle still writes them", %{superuser: user} do
        image = image()
        {archive, key} = bundle(image, user, %{"path" => @repointed, "width" => 999})

        import_bundle(archive, %{key => %{"mode" => "update", "id" => image.id}}, user)

        saved = Repo.get!(Image, image.id)
        assert {saved.path, saved.width} == {@repointed, 999}
      end

      test "a superuser's new image still takes the bundle's path", %{superuser: user} do
        {archive, key} = bundle(image(), user, %{"path" => @repointed})

        import_bundle(archive, %{key => %{"mode" => "create", "publication" => "source"}}, user)

        assert Repo.get_by(Image, path: @repointed)
      end
    end
  end

  describe "LockedFields.held_keys/2" do
    test "holds what every form locks, and not what another form offers" do
      held = LockedFields.held_keys(Image, nil)
      assert :path in held and :width in held and :cdn in held
      refute :title in held

      # Article's `:locked` form locks these; its default form offers them
      article = LockedFields.held_keys(Brando.SyncTest.Article, nil)
      refute :subtitle in article
      refute :year in article
      assert :subtitle in LockedFields.held_keys(Brando.SyncTest.Article, Brando.SyncTest.Article.__form__(:locked))
    end

    test "a form holds its own locks and what the schema holds without one" do
      held = LockedFields.held_keys(Image, %Brando.Blueprint.Forms.Form{tabs: []})
      assert :path in held and :width in held and :cdn in held

      locked = Brando.SyncTest.Article.__form__(:locked)

      assert LockedFields.held_keys(Brando.SyncTest.Article, locked) ==
               LockedFields.keys(Brando.SyncTest.Article, locked, nil)
    end
  end

  describe "the crop editor" do
    setup do
      user = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      root = Storage.current_media_root()
      dir = "images/transfer-locked-#{System.unique_integer([:positive])}"
      File.mkdir_p!(Path.join(root, dir))
      on_exit(fn -> File.rm_rf(Path.join(root, dir)) end)
      %{user: user, root: root, dir: dir}
    end

    defp jpeg do
      {:ok, image} = Elixir.Image.new(10, 10, color: :white)
      Elixir.Image.write!(image, :memory, suffix: ".jpg")
    end

    test "an editor's replace and new copy still work", %{user: user, root: root, dir: dir} do
      path = Path.join(dir, "own.jpg")
      File.write!(Path.join(root, path), "before")
      image = Factory.insert(:image, path: path, width: 100, height: 50, status: :processed)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, replaced} = Crop.save_replace(image, jpeg(), %{x: 50, y: 50}, user)
        assert {replaced.path, replaced.width, replaced.height} == {path, 10, 10}
        refute File.read!(Path.join(root, path)) == "before"

        assert {:ok, copy} = Crop.save_as_new_copy(image, jpeg(), %{x: 50, y: 50}, user)
        assert copy.path != path
        assert File.exists?(Path.join(root, copy.path))
      end)
    end

    test "an editor's replace writes a CDN image whose local original the upload removed",
         %{user: user, root: root, dir: dir} do
      path = Path.join(dir, "uploaded.jpg")
      image = Factory.insert(:image, path: path, width: 100, height: 50, status: :processed, cdn: true)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, replaced} = Crop.save_replace(image, jpeg(), %{x: 50, y: 50}, user)
        assert {replaced.path, replaced.width} == {path, 10}
        assert File.regular?(Path.join(root, path))
      end)
    end

    test "a CDN image still takes only a path under the media root that names an image",
         %{user: user, root: root, dir: dir} do
      path = Path.join(dir, "uploaded.html")
      image = Factory.insert(:image, path: path, width: 100, height: 50, status: :processed, cdn: true)

      assert {:error, :unsafe_media_path} = Crop.save_replace(image, jpeg(), %{x: 50, y: 50}, user)
      refute File.exists?(Path.join(root, path))
    end

    test "a replace writes a stored original the upload form no longer takes", %{user: user, root: root, dir: dir} do
      for name <- ~w(old.avif old.tif old.TIFF old.bmp) do
        path = Path.join(dir, name)
        File.write!(Path.join(root, path), "before")
        image = Factory.insert(:image, path: path, width: 100, height: 50, status: :processed)

        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:ok, _} = Crop.save_replace(image, jpeg(), %{x: 50, y: 50}, user)
          refute File.read!(Path.join(root, path)) == "before"
        end)
      end
    end

    test "a replace doesn't write a file that isn't an image's", %{user: user, root: root, dir: dir} do
      for name <- ~w(brochure.pdf page.html page.htm script.js noextension) do
        other = Path.join(dir, name)
        File.write!(Path.join(root, other), "untouched")
        image = Factory.insert(:image, path: other, width: 100, height: 50, status: :processed)

        assert {:error, :unsafe_media_path} = Crop.save_replace(image, jpeg(), %{x: 50, y: 50}, user)
        assert File.read!(Path.join(root, other)) == "untouched"
      end
    end

    test "a replace doesn't create a file", %{user: user, root: root, dir: dir} do
      missing = Path.join(dir, "new.jpg")
      image = Factory.insert(:image, path: missing, width: 100, height: 50, status: :processed)

      assert {:error, :unsafe_media_path} = Crop.save_replace(image, jpeg(), %{x: 50, y: 50}, user)
      refute File.exists?(Path.join(root, missing))
    end
  end
end
