defmodule BrandoAdmin.GlobalValuesPermissionTest do
  # With groups, `update_values` on global sets fills in values on the Globals
  # screen and nothing else: adding, removing or retyping a global, its options
  # and its label take `update`, which includes filling in values. Crafted
  # events and direct context calls are tried as a member of each.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Catalog, Engine, Groups, Migration, Scope}
  alias Brando.Sites
  alias Brando.Sites.GlobalSet
  alias Brando.Test.Users, as: TestUsers

  @read "brando.sites_global_sets.read"
  @update "brando.sites_global_sets.update"
  @values "brando.sites_global_sets.update_values"

  setup %{current_user: owner} do
    preserve_cache(:globals)

    {:ok, set} =
      Sites.create_global_set(
        %{
          label: "Settings",
          key: "settings",
          language: "en",
          vars: [
            %{key: "tagline", label: "Tagline", type: :string, value: "Hello", creator_id: owner.id},
            %{
              key: "size",
              label: "Size",
              type: :select,
              value: "small",
              options: [%{label: "Small", value: "small"}, %{label: "Large", value: "large"}],
              creator_id: owner.id
            }
          ]
        },
        owner
      )

    %{owner: owner, set: set}
  end

  defp saved(set), do: GlobalSet |> Repo.get!(set.id) |> Repo.preload(:vars)
  defp saved_var(set, key), do: Enum.find(saved(set).vars, &(&1.key == key))
  defp var_id(set, key), do: saved_var(set, key).id

  defp open_globals(conn) do
    {:ok, view, _html} = live(conn, "/admin/globals")
    render_async(view)
    view
  end

  defp submit_globals(view, set, params) do
    view
    |> element("[id^='set-'] form")
    |> render_submit(%{"global_set" => Map.put(params, "id", set.id)})
  end

  # The set as `params` would change it, as a save built elsewhere would send
  # it under the values permission.
  defp values_save(set, params, user) do
    set = saved(set)
    set |> GlobalSet.changeset(params, user) |> Sites.update_global_set(user, action: :update_values)
  end

  defp member(owner, keys) do
    user = TestUsers.insert_user(role: :editor)
    scope = Scope.standalone(owner)
    {:ok, group} = Groups.create(scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
    {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
    user
  end

  # A page save carrying a var with another owner's key: the var stays the
  # page's, and neither the set nor the module gains it.
  defp plant_through_page(owner, editor, set) do
    module = Brando.ProposalFixtures.module!(owner, "Planted", "<p>{{ title }}</p>", [])

    page =
      :page |> Factory.insert(creator: owner, title: "Planted", uri: "planted", status: :draft) |> Repo.preload(:vars)

    vars = %{
      "0" => %{"key" => "in_set", "type" => "string", "label" => %{"en" => "S"}, "global_set_id" => set.id},
      "1" => %{"key" => "in_module", "type" => "string", "label" => %{"en" => "M"}, "module_id" => module.id}
    }

    assert {:ok, _} = page |> Brando.Pages.Page.changeset(%{"vars" => vars}, editor) |> Brando.Pages.update_page(editor)

    assert [_, _] = saved(set).vars
    assert Repo.preload(module, :vars, force: true).vars == []
    assert ["in_module", "in_set"] = Repo.preload(page, :vars, force: true).vars |> Enum.map(& &1.key) |> Enum.sort()
  end

  describe "groups mode" do
    setup %{owner: owner} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      {:ok, _} = Migration.run()

      values = member(owner, ["brando.admin.access", @read, @values])
      updater = member(owner, ["brando.admin.access", @read, @update])
      reader = member(owner, ["brando.admin.access", @read])

      %{values: values, updater: updater, reader: reader}
    end

    test "a values member saves a value on the Globals screen", %{values: values, set: set} do
      view = open_globals(log_in_user(build_conn(), values))
      assert has_element?(view, ".global-save-actions button")

      submit_globals(view, set, %{"vars" => %{"0" => %{"id" => var_id(set, "tagline"), "value" => "By values"}}})
      assert saved_var(set, "tagline").value == "By values"
    end

    test "a values member's crafted definition beside a value changes only the value",
         %{values: values, set: set} do
      view = open_globals(log_in_user(build_conn(), values))

      submit_globals(view, set, %{
        "key" => "renamed",
        "label" => "Renamed",
        "vars" => %{
          "0" => %{
            "id" => var_id(set, "tagline"),
            "type" => "html",
            "key" => "renamed",
            "label" => %{"en" => "Relabelled"},
            "value" => "New"
          },
          "1" => %{
            "id" => var_id(set, "size"),
            "value" => "large",
            "options" => %{"0" => %{"label" => "Crafted", "value" => "crafted"}}
          },
          "2" => %{"key" => "planted", "type" => "string", "value" => "x"}
        }
      })

      assert %{key: "settings", label: "Settings", vars: [_, _]} = saved(set)
      assert %{type: :string, key: "tagline", label: %{"en" => "Tagline"}, value: "New"} = saved_var(set, "tagline")
      assert %{value: "large", options: [%{value: "small"}, %{value: "large"}]} = saved_var(set, "size")
    end

    # Globals moved to vars by brando_109 have no sequence, and vars a seed or
    # an import wrote as `:system` no creator. A save numbers the vars by
    # their place and stamps an empty creator.
    test "a values member saves a value in a set stored with no sequence or creator",
         %{values: values, set: set} do
      Repo.update_all(from(v in Brando.Content.Var, where: v.global_set_id == ^set.id),
        set: [sequence: nil, creator_id: nil]
      )

      Repo.update_all(from(s in GlobalSet, where: s.id == ^set.id), set: [creator_id: nil])

      view = open_globals(log_in_user(build_conn(), values))
      submit_globals(view, set, %{"vars" => %{"0" => %{"id" => var_id(set, "tagline"), "value" => "On screen"}}})
      assert saved_var(set, "tagline").value == "On screen"

      params = %{"vars" => %{"0" => %{"id" => var_id(set, "size"), "value" => "large"}}}
      assert {:ok, _} = Sites.update_global_values(saved(set), params, values)
      assert %{value: "large", sequence: nil} = saved_var(set, "size")
      assert saved(set).creator_id == values.id
    end

    # The Globals screen saves with the set it loaded when it opened: the
    # creator another save stamped since then stands.
    test "a values save from a stale screen keeps the creator another save stamped",
         %{values: values, owner: owner, set: set} do
      Repo.update_all(from(v in Brando.Content.Var, where: v.global_set_id == ^set.id), set: [creator_id: nil])
      Repo.update_all(from(s in GlobalSet, where: s.id == ^set.id), set: [creator_id: nil])

      stale = saved(set)
      first = member(owner, ["brando.admin.access", @read, @values])
      tagline = var_id(set, "tagline")

      save = fn value, user ->
        Sites.update_global_values(stale, %{"vars" => %{"0" => %{"id" => tagline, "value" => value}}}, user)
      end

      assert {:ok, _} = save.("First", first)
      assert {:ok, _} = save.("Second", values)

      assert saved(set).creator_id == first.id
      assert %{value: "Second", creator_id: tagline_creator} = saved_var(set, "tagline")
      assert tagline_creator == first.id
      assert saved_var(set, "size").creator_id == first.id
    end

    # Unnumbered globals (brando_109) keep no sequence, so a save that
    # changes no value is no edit of the set.
    test "a values save with no value changed leaves a set with unnumbered globals unedited",
         %{values: values, set: set} do
      Repo.update_all(from(v in Brando.Content.Var, where: v.global_set_id == ^set.id), set: [sequence: nil])

      before = saved(set)
      tagline = var_id(set, "tagline")

      save = fn value ->
        Sites.update_global_values(saved(set), %{"vars" => %{"0" => %{"id" => tagline, "value" => value}}}, values)
      end

      assert {:ok, _} = save.("Hello")
      assert Map.take(saved(set), [:edited_at, :updated_by_id]) == Map.take(before, [:edited_at, :updated_by_id])

      assert {:ok, _} = save.("Changed")
      assert %{value: "Changed", sequence: nil} = saved_var(set, "tagline")
      assert saved(set).updated_by_id == values.id
      assert saved_var(set, "size").sequence == nil
    end

    test "a values save does not hand a var to another creator", %{values: values, owner: owner, set: set} do
      other = TestUsers.insert_user(role: :editor)
      tagline = var_id(set, "tagline")
      params = %{"vars" => %{"0" => %{"id" => tagline, "creator_id" => other.id}, "1" => %{"id" => var_id(set, "size")}}}

      assert {:error, :forbidden} = values_save(set, params, values)
      assert saved_var(set, "tagline").creator_id == owner.id
    end

    # Which palette a colour global offers is its definition.
    test "a values member's crafted palette is not saved", %{values: values, owner: owner, set: set} do
      offered = Factory.insert(:palette, creator: owner)
      crafted = Factory.insert(:palette, key: "crafted", creator: owner)

      colour =
        %Brando.Content.Var{global_set_id: set.id, sequence: 2}
        |> Brando.Content.Var.changeset(
          %{key: "colour", label: "Colour", type: :color, color_picker: true, palette_id: offered.id},
          owner
        )
        |> Repo.insert!()

      view = open_globals(log_in_user(build_conn(), values))

      submit_globals(view, set, %{
        "vars" => %{"2" => %{"id" => colour.id, "value" => "#445566", "palette_id" => crafted.id}}
      })

      assert %{value: "#445566", palette_id: palette_id} = saved_var(set, "colour")
      assert palette_id == offered.id
    end

    test "the setup screens are closed to a values member", %{values: values, set: set} do
      conn = log_in_user(build_conn(), values)

      for path <- ["/admin/config/global_sets/create", "/admin/config/global_sets/update/#{set.id}"] do
        assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, path)
      end
    end

    test "a values member is refused every change to a definition through the context",
         %{values: values, set: set} do
      tagline = var_id(set, "tagline")
      size = var_id(set, "size")
      both = fn tagline_row -> %{"vars" => %{"0" => tagline_row, "1" => %{"id" => size}}} end

      # Through `update`, which the generic save and every import take.
      assert {:error, :forbidden} =
               Sites.update_global_set(set.id, both.(%{"id" => tagline, "value" => "x"}), values)

      assert {:error, :forbidden} = Sites.create_global_set(%{label: "New", key: "new", language: "en"}, values)
      assert {:error, :forbidden} = Sites.delete_global_set(set.id, values)

      # Through `update_values`, with a definition in the change.
      for {what, params} <- [
            retype: both.(%{"id" => tagline, "type" => "html"}),
            rekey: both.(%{"id" => tagline, "key" => "renamed"}),
            relabel: both.(%{"id" => tagline, "label" => %{"en" => "Relabelled"}}),
            options: %{
              "vars" => %{
                "0" => %{"id" => tagline},
                "1" => %{"id" => size, "options" => [%{"label" => "Crafted", "value" => "crafted"}]}
              }
            },
            add: %{"vars" => %{"0" => %{"id" => tagline}, "1" => %{"id" => size}, "2" => %{"key" => "new"}}},
            remove: %{"vars" => %{"0" => %{"id" => tagline}}},
            rename: %{"label" => "Renamed"}
          ] do
        assert {:error, :forbidden} = values_save(set, params, values), "#{what} was let through"
      end

      assert {:ok, _} = values_save(set, both.(%{"id" => tagline, "value" => "Value"}), values)

      assert %{key: "settings", label: "Settings", vars: [_, _]} = saved(set)
      assert %{type: :string, key: "tagline", value: "Value"} = saved_var(set, "tagline")
      assert [_, _] = saved_var(set, "size").options

      assert {:ok, _} = Sites.update_global_values(saved(set), both.(%{"id" => tagline, "value" => "Again"}), values)
      assert saved_var(set, "tagline").value == "Again"
    end

    test "an update member changes definitions and values", %{updater: updater, set: set} do
      tagline = var_id(set, "tagline")
      size = var_id(set, "size")

      assert {:ok, _} =
               Sites.update_global_set(
                 set.id,
                 %{"vars" => %{"0" => %{"id" => tagline, "type" => "text"}, "1" => %{"id" => size}}},
                 updater
               )

      assert saved_var(set, "tagline").type == :text

      view = open_globals(log_in_user(build_conn(), updater))
      submit_globals(view, set, %{"vars" => %{"0" => %{"id" => tagline, "value" => "By updater"}}})
      assert saved_var(set, "tagline").value == "By updater"

      assert {:ok, _view, _html} = live(log_in_user(build_conn(), updater), "/admin/config/global_sets/update/#{set.id}")
    end

    test "a reader sees the values, with no save, and a crafted save is refused", %{reader: reader, set: set} do
      view = open_globals(log_in_user(build_conn(), reader))
      refute has_element?(view, ".global-save-actions")

      submit_globals(view, set, %{"vars" => %{"0" => %{"id" => var_id(set, "tagline"), "value" => "By reader"}}})
      assert saved_var(set, "tagline").value == "Hello"
      assert {:error, :forbidden} = Sites.update_global_values(saved(set), %{}, reader)
    end

    test "update includes the values permission, which the Editor preset holds alone",
         %{values: values, updater: updater} do
      assert Engine.can?(Scope.standalone(updater), :update_values, GlobalSet)
      refute Engine.can?(Scope.standalone(values), :update, GlobalSet)

      editor = Catalog.preset_permissions(:editor, :standalone)
      assert @values in editor
      refute @update in editor
      assert @values in Catalog.preset_permissions(:admin, :site)
    end

    test "a page save cannot add a var to a global set or a module", %{owner: owner, set: set} do
      editor = member(owner, Catalog.preset_permissions(:editor, :standalone))
      plant_through_page(owner, editor, set)
    end

    test "a manager holding update may grant the values permission", %{owner: owner} do
      manager = member(owner, ["brando.admin.access", "brando.groups.read", "brando.groups.create", @update])

      assert {:ok, _} = Groups.create(Scope.standalone(manager), %{name: "Values"}, ["brando.admin.access", @values])
      assert {:error, :not_delegable} = Groups.create(Scope.standalone(manager), %{name: "Read"}, [@read])
    end
  end

  describe "legacy mode" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      :ok
    end

    test "an editor fills in values and a user is refused", %{set: set} do
      editor = TestUsers.insert_user(role: :editor)
      user = TestUsers.insert_user(role: :user)
      params = %{"vars" => %{"0" => %{"id" => var_id(set, "tagline"), "value" => "By editor"}}}

      assert {:ok, _} = Sites.update_global_values(saved(set), params, editor)
      assert saved_var(set, "tagline").value == "By editor"
      assert {:error, :forbidden} = Sites.update_global_values(saved(set), params, user)
    end

    test "a page save cannot add a var to a global set or a module", %{owner: owner, set: set} do
      plant_through_page(owner, TestUsers.insert_user(role: :editor), set)
    end

    # What a proposal creating a var applies (`Brando.Content.Proposals`).
    test "a var created on its own does not join a global set", %{set: set} do
      editor = TestUsers.insert_user(role: :editor)
      params = %{key: "planted", label: %{"en" => "Planted"}, type: :string, global_set_id: set.id}

      assert {:ok, %{global_set_id: nil}} = Brando.Content.create_var(params, editor)
      assert [_, _] = saved(set).vars
    end

    test "a values save carries no definition", %{set: set} do
      editor = TestUsers.insert_user(role: :editor)
      params = %{"vars" => %{"0" => %{"id" => var_id(set, "tagline"), "type" => "html"}}}
      assert {:error, :forbidden} = values_save(set, params, editor)
    end
  end
end
