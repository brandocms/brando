defmodule Brando.Content.SharedLibraryTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Content.Module
  alias Brando.Content.ModuleResolver
  alias Brando.Content.SharedLibrary
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @prefix "tenant_library-test_preview"

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    SharedLibrary.Cache.clear()

    user = Brando.Factory.insert(:random_user, role: :superuser)

    {:ok, site} =
      Registry.create_site(%{
        name: "Library test",
        key: "library-test",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{
        name: "Preview",
        key: "preview",
        live: true
      })

    Ecto.Adapters.SQL.query!(BrandoIntegration.Repo, ~s|CREATE SCHEMA "#{@prefix}"|)

    for table <- ~w(content_modules content_vars content_refs content_containers content_palettes content_blocks) do
      Ecto.Adapters.SQL.query!(
        BrandoIntegration.Repo,
        ~s|CREATE TABLE "#{@prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|
      )
    end

    on_exit(fn ->
      Tenant.put_prefix(nil)
      SharedLibrary.Cache.clear()
    end)

    %{site: site, user: user}
  end

  test "fully custom, hybrid, and disabled rendering behavior", %{site: site, user: user} do
    shared = create_public_module("Shared hero", user)
    local = Tenant.with_prefix(@prefix, fn -> create_module("Site hero", user) end)

    assert [%{id: local_id, library_origin: :local}] =
             SharedLibrary.list_available(:module, site, @prefix)

    assert local_id == local.id
    refute SharedLibrary.get(:module, shared.id, :shared, site, @prefix, require_enabled: true)

    assert :ok = SharedLibrary.enable(site, :module, shared.id)

    available =
      site
      |> then(&SharedLibrary.list_available(:module, &1, @prefix))
      |> Enum.map(&{&1.id, &1.library_origin})
      |> MapSet.new()

    assert available == MapSet.new([{local.id, :local}, {shared.id, :shared}])

    assert %{id: shared_id, library_origin: :shared} =
             SharedLibrary.get(:module, shared.id, :shared, site, @prefix, require_enabled: true)

    assert shared_id == shared.id
    assert :ok = SharedLibrary.disable(site, :module, shared.id)
    assert [%{id: remaining_id}] = SharedLibrary.list_available(:module, site, @prefix)
    assert remaining_id == local.id

    # Revoking picker access must not break blocks already referencing shared.
    assert %{id: rendered_id, library_origin: :shared} =
             SharedLibrary.get(:module, shared.id, :shared, site, @prefix)

    assert rendered_id == shared.id
  end

  test "customize, dismiss, accept, and reset preserve the shared block identity", %{site: site, user: user} do
    shared = create_public_module("Shared testimonial", user)
    assert :ok = SharedLibrary.enable(site, :module, shared.id)

    assert {:ok, override} = SharedLibrary.customize(:module, shared.id, site, @prefix, user)
    assert override.source_module_id == shared.id
    assert override.source_version == 1

    assert [
             %{
               id: effective_id,
               override_id: override_id,
               source_module_id: source_id,
               update_available: false
             }
           ] =
             SharedLibrary.list_available(:module, site, @prefix)

    assert effective_id == shared.id
    assert override_id == override.id
    assert source_id == shared.id

    assert {:ok, shared_v2} =
             SharedLibrary.update_shared(
               :module,
               shared.id,
               %{help_text: %{"en" => "Version two"}, version_note: "Add a field"},
               user
             )

    assert shared_v2.version == 2
    assert [%{update_available: true}] = SharedLibrary.list_available(:module, site, @prefix)

    assert {:ok, _dismissed} = SharedLibrary.dismiss_update(:module, shared.id, site, @prefix)
    assert [%{update_available: false}] = SharedLibrary.list_available(:module, site, @prefix)

    assert {:ok, accepted} = SharedLibrary.accept_update(:module, shared.id, site, @prefix, user)
    assert accepted.source_version == 2
    assert accepted.help_text == %{"en" => "Version two"}

    assert :ok = SharedLibrary.reset(:module, shared.id, site, @prefix)

    assert %{source_module_id: nil, version: 2} =
             SharedLibrary.get(:module, shared.id, :shared, site, @prefix)
  end

  test "containers and palettes use the same allowlist and override contract", %{site: site, user: user} do
    palette = create_public_palette("Shared dark", user)
    container = create_public_container("Shared section", user)

    assert :ok = SharedLibrary.set_enabled(site, :palette, [palette.id])
    assert :ok = SharedLibrary.set_enabled(site, :container, [container.id])

    assert [%{id: palette_id, library_origin: :shared}] =
             SharedLibrary.list_available(:palette, site, @prefix)

    assert [%{id: container_id, library_origin: :shared}] =
             SharedLibrary.list_available(:container, site, @prefix)

    assert palette_id == palette.id
    assert container_id == container.id

    assert {:ok, palette_override} =
             SharedLibrary.customize(:palette, palette.id, site, @prefix, user)

    assert {:ok, container_override} =
             SharedLibrary.customize(:container, container.id, site, @prefix, user)

    assert palette_override.source_palette_id == palette.id
    assert container_override.source_container_id == container.id
  end

  test "module customization copies editable variables and references", %{site: site, user: user} do
    attrs =
      "Shared rich module"
      |> module_attrs()
      |> Map.put(:vars, [
        %{
          type: :text,
          label: "Eyebrow",
          key: "eyebrow",
          value: "Shared value",
          sequence: 0
        }
      ])
      |> Map.put(:refs, [
        %{
          name: "body",
          description: "Body copy",
          uid: Brando.Utils.generate_uid(),
          sequence: 0,
          data: %{type: "text", data: %{text: "Shared body"}}
        }
      ])

    assert {:ok, shared} = SharedLibrary.create_shared(:module, attrs, user)
    assert :ok = SharedLibrary.enable(site, :module, shared.id)
    assert {:ok, override} = SharedLibrary.customize(:module, shared.id, site, @prefix, user)

    assert [%{key: "eyebrow", value: "Shared value", module_id: override_id}] = override.vars
    assert override_id == override.id
    assert [%{name: "body", description: "Body copy", module_id: ref_override_id}] = override.refs
    assert ref_override_id == override.id
  end

  test "origin-qualified block fields round-trip independently from integer IDs" do
    changeset =
      Block.block_changeset(
        %Block{},
        %{
          uid: "shared-origin",
          module_id: 42,
          module_origin: "shared",
          container_id: 42,
          container_origin: "local",
          palette_id: 42,
          palette_origin: "shared"
        },
        :system
      )

    block = Ecto.Changeset.apply_changes(changeset)
    assert block.module_id == block.container_id
    assert block.module_origin == :shared
    assert block.container_origin == :local
    assert block.palette_origin == :shared
  end

  test "shared references have an unambiguous picker encoding" do
    assert {:shared, 42} = "shared:42" |> SharedLibrary.reference()
    assert {:local, 42} = "42" |> SharedLibrary.reference()
    assert "shared:42" == SharedLibrary.encode_reference(:shared, 42)
  end

  test "tenant-first compatibility and explicit origins survive integer ID collisions", %{
    site: site,
    user: user
  } do
    shared = create_public_module("Shared collision", user)

    local =
      Tenant.with_prefix(@prefix, fn ->
        {:ok, module} =
          %Module{id: shared.id}
          |> Module.changeset(module_attrs("Local collision"), user)
          |> Repo.insert()

        module
      end)

    assert local.id == shared.id
    assert :ok = SharedLibrary.enable(site, :module, shared.id)

    assert %{name: %{"en" => "Local collision"}, library_origin: :local} =
             ModuleResolver.get_module(shared.id, site, @prefix)

    assert %{name: %{"en" => "Shared collision"}, library_origin: :shared} =
             ModuleResolver.get_module(shared.id, :shared, site, @prefix)
  end

  test "deletion remains blocked after access is revoked when an existing block still references shared", %{
    site: site,
    user: user
  } do
    shared = create_public_module("Shared in use", user)
    assert :ok = SharedLibrary.enable(site, :module, shared.id)
    assert {:error, {:shared_item_in_use, _usage}} = SharedLibrary.delete_shared(:module, shared.id)

    assert :ok = SharedLibrary.disable(site, :module, shared.id)
    refute Enum.any?(SharedLibrary.list_for_rendering(:module, site, @prefix), &(&1.id == shared.id))

    Ecto.Adapters.SQL.query!(
      BrandoIntegration.Repo,
      ~s|INSERT INTO "#{@prefix}".content_blocks (uid, type, module_id, module_origin, inserted_at, updated_at) VALUES ('shared-in-use', 'module', $1, 'shared', now(), now())|,
      [shared.id]
    )

    assert {:error, {:shared_item_in_use, [usage]}} = SharedLibrary.delete_shared(:module, shared.id)
    refute usage.enabled
    assert usage.referenced_environments == ["preview"]

    assert Enum.any?(SharedLibrary.list_for_rendering(:module, site, @prefix), fn entry ->
             entry.id == shared.id and entry.library_origin == :shared
           end)
  end

  defp create_public_module(name, user) do
    Tenant.put_prefix(nil)

    {:ok, module} = SharedLibrary.create_shared(:module, module_attrs(name), user)
    module
  end

  defp create_module(name, user) do
    {:ok, module} =
      %Module{}
      |> Module.changeset(module_attrs(name), user)
      |> Repo.insert()

    module
  end

  defp module_attrs(name) do
    %{
      name: %{"en" => name},
      namespace: %{"en" => "general"},
      help_text: %{"en" => "Help"},
      class: "module",
      code: "<section>#{name}</section>"
    }
  end

  defp create_public_container(name, user) do
    Tenant.put_prefix(nil)

    {:ok, container} =
      SharedLibrary.create_shared(
        :container,
        %{
          name: name,
          namespace: "general",
          help_text: "Help",
          code: "<section>{{ content }}</section>"
        },
        user
      )

    container
  end

  defp create_public_palette(name, user) do
    Tenant.put_prefix(nil)

    {:ok, palette} =
      SharedLibrary.create_shared(
        :palette,
        %{
          name: name,
          key: "sharedDark",
          namespace: "general",
          status: :published,
          colors: []
        },
        user
      )

    palette
  end
end
