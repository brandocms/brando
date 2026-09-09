defmodule BrandoAdmin.ModuleFilesTest do
  use Brando.LiveCase
  alias Brando.Content.{Definitions, Module}
  alias Brando.Content.Definition.Archive
  alias Ecto.Changeset

  setup %{current_user: user} do
    source = File.read!("test/fixtures/definitions/hero.exs.txt")
    {:ok, binary} = Archive.pack(%{"hero.exs" => source})
    {:ok, archive} = Archive.read(binary)
    {:ok, plan} = Definitions.plan(archive.bundle, user)
    {:ok, _} = Definitions.apply(plan, user)
    %{module: Repo.get_by!(Module, uid: "hero-test")}
  end

  defp download(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Floki.attribute("href")
    |> hd()
    |> String.replace_prefix("data:application/zip;base64,", "")
    |> Base.decode64!()
  end

  defp upload(view, binary) do
    input =
      file_input(view, "#module-files-import-form", :definition_zip, [
        %{name: "modules.zip", content: binary, type: "application/zip"}
      ])

    render_upload(input, "modules.zip")
    view |> form("#module-files-import-form", references: "") |> render_submit()
  end

  defp export(view) do
    view |> element("#module-files button[phx-click=export]") |> render_click()
    download(view, "#module-files-download")
  end

  defp edited(binary, class) do
    {:ok, archive} = Archive.read(binary)

    files =
      Map.new(archive.files, fn {name, body} ->
        if String.ends_with?(name, ".exs"),
          do: {name, String.replace(body, "class \"hero\"", "class \"#{class}\"")},
          else: {name, body}
      end)

    {:ok, binary} = Archive.pack(files)
    binary
  end

  test "admin export, preview, apply and updated ZIP form an identity-preserving round trip", c do
    {:ok, view, _} = live(c.conn, "/admin/config/content/modules")
    binary = export(view)
    html = upload(view, edited(binary, "from-admin-zip"))
    assert html =~ "Review import"
    assert html =~ "Nothing has been applied"
    assert html =~ "from-admin-zip"
    assert Repo.get!(Module, c.module.id).class == "hero"
    assert view |> element("#module-files-apply") |> render_click() =~ "Import complete"
    after_import = Repo.get!(Module, c.module.id)
    assert after_import.class == "from-admin-zip"
    assert after_import.version == c.module.version + 1

    updated = download(view, "#module-files-updated-download")
    assert {:ok, archive} = Archive.read(updated)
    assert {:ok, plan} = Definitions.plan(archive.bundle, c.current_user)
    assert [%{action: :noop}] = plan.items
    view |> element("#module-files button[phx-click=reset]") |> render_click()
    upload(view, updated)
    view |> element("#module-files-apply") |> render_click()
    assert Repo.get!(Module, c.module.id) == after_import
    assert Repo.aggregate(Module, :count) == 1
  end

  test "conflicts disable apply and stale previews cannot overwrite admin edits", c do
    {:ok, view, _} = live(c.conn, "/admin/config/content/modules")
    binary = edited(export(view), "desired")
    upload(view, binary)
    c.module |> Changeset.change(class: "concurrent") |> Repo.update!()
    assert view |> element("#module-files-apply") |> render_click() =~ "target changed"
    assert Repo.get!(Module, c.module.id).class == "concurrent"
    html = view |> form("#module-files-import-form", references: "") |> render_submit()
    assert html =~ "Conflict"
    assert has_element?(view, "#module-files-apply[disabled]")
    assert Repo.get!(Module, c.module.id).class == "concurrent"
  end

  test "selected export includes only the selected module tree", c do
    %Module{}
    |> Module.changeset(
      %{
        uid: "other-module",
        name: %{"en" => "Other"},
        namespace: %{"en" => "General"},
        help_text: %{"en" => "Another module"},
        class: "other",
        code: "<p>Other</p>",
        type: :liquid
      },
      c.current_user
    )
    |> Repo.insert!()

    {:ok, view, _} = live(c.conn, "/admin/config/content/modules")
    render_click(view, "export_module_files", %{ids: Jason.encode!([c.module.id])})
    assert {:ok, archive} = view |> export() |> Archive.read()
    assert [%{"uid" => "hero-test"}] = archive.bundle["modules"]
  end

  test "cancel, malformed input and edited mappings discard the previous preview", c do
    {:ok, view, _} = live(c.conn, "/admin/config/content/modules")
    binary = export(view)
    upload(view, binary)
    view |> element("#module-files button[phx-click=reset]") |> render_click()
    refute has_element?(view, "#module-files-preview")
    assert upload(view, "broken") =~ "expected a valid ZIP"
    upload(view, binary)
    view |> element("#module-files button[phx-click=reset]") |> render_click()

    input =
      file_input(view, "#module-files-import-form", :definition_zip, [
        %{name: "modules.zip", content: binary, type: "application/zip"}
      ])

    render_upload(input, "modules.zip")
    assert view |> form("#module-files-import-form", references: "[]") |> render_submit() =~ "JSON object"
    refute has_element?(view, "#module-files-apply")
    assert Repo.get!(Module, c.module.id).version == c.module.version
  end

  test "a viewer cannot forge component export or import events", c do
    put_test_env(:authorization_mode, :groups)
    alias Brando.Authorization.{Catalog, Groups, Migration, Scope}
    assert {:ok, _} = Migration.run()
    viewer = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    scope = Scope.standalone(c.current_user)
    grants = ["brando.admin.access", Catalog.get(:read, Module).key]
    assert {:ok, group} = Groups.create(scope, %{name: "Module viewers"}, grants)
    assert {:ok, :ok} = Groups.add_member(scope, group.id, viewer.id)
    conn = log_in_user(Phoenix.ConnTest.build_conn(), viewer)
    {:ok, view, _} = live(conn, "/admin/config/content/modules")
    assert has_element?(view, "#module-files button[phx-click=export][disabled]")
    assert render_click(view, "export_module_files", %{ids: Jason.encode!([c.module.id])}) =~ "permission"
    refute has_element?(view, "#module-files-download")
    assert view |> form("#module-files-import-form", references: "") |> render_submit() =~ "permission"
    assert Repo.get!(Module, c.module.id).version == c.module.version
  end

  test "reference mappings can be supplied after reading the uploaded bundle", c do
    image = Factory.insert(:image)

    source =
      File.read!("test/fixtures/definitions/hero.exs.txt")
      |> String.replace("uid \"hero-test\"", "uid \"with-cover\"")
      |> String.replace("description \"Headline\"", "description \"Headline\"\n      assets image: \"cover\"")

    {:ok, binary} = Archive.pack(%{"hero.exs" => source})
    {:ok, view, _} = live(c.conn, "/admin/config/content/modules")
    assert upload(view, binary) =~ "requires a destination reference mapping"
    refute has_element?(view, "#module-files-apply")

    mappings = Jason.encode!(%{"cover" => image.id})
    view |> form("#module-files-import-form", references: mappings) |> render_change()
    assert view |> form("#module-files-import-form", references: mappings) |> render_submit() =~ "Review import"
    view |> element("#module-files-apply") |> render_click()
    module = Repo.get_by!(Module, uid: "with-cover") |> Repo.preload(:refs)
    assert hd(module.refs).image_id == image.id
  end
end
