defmodule BrandoAdmin.VarGuardLiveTest do
  # The block editor's and the Globals screen's saves, as an editor's browser
  # sends them with a crafted type, key or option beside a value, in both
  # authorization modes.
  use Brando.LiveCase

  alias Brando.Content.Var
  alias Brando.ProposalFixtures
  alias Brando.Sites.GlobalSet

  @payloads "test/fixtures/editor_sinks/payloads.json" |> File.read!() |> Jason.decode!()
  @handler @payloads["handler"]

  setup %{current_user: superuser} do
    preserve_cache(:globals)
    editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})

    {:ok, set} =
      Brando.Sites.create_global_set(
        %{
          label: "Settings",
          key: "settings",
          language: "en",
          vars: [
            %{key: "tagline", label: "Tagline", type: :string, value: "Hello", creator_id: superuser.id},
            %{
              key: "size",
              label: "Size",
              type: :select,
              value: "small",
              options: [%{label: "Small", value: "small"}],
              creator_id: superuser.id
            }
          ]
        },
        superuser
      )

    %{editor: editor, editor_conn: log_in_user(build_conn(), editor), set: set}
  end

  defp await(condition, attempts \\ 100) do
    cond do
      condition.() -> :ok
      attempts == 0 -> flunk("the condition was not met")
      true -> Process.sleep(20) && await(condition, attempts - 1)
    end
  end

  defp open_globals(conn) do
    {:ok, view, _html} = live(conn, "/admin/globals")
    render_async(view)
    view
  end

  defp saved(set), do: GlobalSet |> Repo.get!(set.id) |> Repo.preload(:vars)
  defp saved_var(set, key), do: Enum.find(saved(set).vars, &(&1.key == key))

  defp submit_globals(conn, set, vars) do
    view = open_globals(conn)
    view |> element("form[phx-submit=submit]") |> render_submit(%{"global_set" => %{"id" => set.id, "vars" => vars}})
  end

  defp var_id(set, key), do: saved_var(set, key).id

  describe "the Globals screen" do
    test "a value saves", %{conn: conn, set: set} do
      submit_globals(conn, set, %{"0" => %{"id" => var_id(set, "tagline"), "value" => "New"}})
      assert saved_var(set, "tagline").value == "New"
    end

    test "a crafted type, key or option does not change the definition", %{conn: conn, set: set} do
      submit_globals(conn, set, %{
        "0" => %{"id" => var_id(set, "tagline"), "type" => "select", "key" => "renamed", "value" => "New"},
        "2" => %{"key" => "planted", "type" => "string", "value" => "x"}
      })

      assert %{type: :string, value: "New"} = saved_var(set, "tagline")
      assert [_, _] = saved(set).vars
    end

    test "a set's vars and name stay when the params leave them out", %{conn: conn, set: set} do
      view = open_globals(conn)

      view
      |> element("form[phx-submit=submit]")
      |> render_submit(%{"global_set" => %{"id" => set.id, "key" => "renamed", "label" => "Renamed", "vars" => %{}}})

      assert %{key: "settings", label: "Settings", vars: [_, _]} = saved(set)
    end

    test "a select value with a matching crafted option is refused", %{conn: conn, set: set} do
      submit_globals(conn, set, %{
        "0" => %{
          "id" => var_id(set, "size"),
          "value" => @handler,
          "options" => %{"0" => %{"label" => "Crafted", "value" => @handler}}
        }
      })

      assert %{value: "small", options: [%{value: "small"}]} = saved_var(set, "size")
    end
  end

  describe "the setup of global sets" do
    for path <- ["/admin/config/global_sets", "/admin/config/global_sets/create"] do
      test "#{path} is closed to a legacy editor, open to a superuser", %{conn: conn, editor_conn: editor_conn} do
        put_test_env(:authorization_mode, :legacy)
        assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(editor_conn, unquote(path))
        assert {:ok, _view, _html} = live(conn, unquote(path))
      end
    end

    test "the update form is closed to a legacy editor", %{editor_conn: editor_conn, set: set} do
      put_test_env(:authorization_mode, :legacy)
      path = "/admin/config/global_sets/update/#{set.id}"
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(editor_conn, path)
    end

    test "the Globals screen stays open to a legacy editor", %{editor_conn: editor_conn, set: set} do
      put_test_env(:authorization_mode, :legacy)
      submit_globals(editor_conn, set, %{"0" => %{"id" => var_id(set, "tagline"), "value" => "By editor"}})
      assert saved_var(set, "tagline").value == "By editor"
    end
  end

  describe "the block editor" do
    setup %{current_user: superuser} do
      module =
        ProposalFixtures.module!(superuser, "Printed", "<p>{{ title }}</p>",
          vars: [%{type: "string", key: "title", label: "Title", value: "Start"}]
        )

      page = Factory.insert(:page, creator: superuser, title: "Crafted", uri: "crafted")

      block =
        %Brando.Content.Block{}
        |> Brando.Content.Block.recursive_block_changeset(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => module.id,
            "source" => "Elixir.Brando.Pages.Page.Blocks",
            "vars" => %{"0" => %{"key" => "title", "label" => "Title", "value" => "Start"}}
          },
          superuser
        )
        |> Repo.insert!()

      Repo.insert!(%Brando.Pages.Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
      %{page: page, block: Repo.preload(block, :vars)}
    end

    for mode <- [:legacy, :groups] do
      test "a crafted type and key do not reach the saved var, in #{mode} mode", c do
        if unquote(mode) == :groups do
          put_test_env(:authorization_mode, :groups)
          {:ok, _} = Brando.Authorization.Migration.run()
        end

        conn = if unquote(mode) == :groups, do: c.conn, else: c.editor_conn
        {view, _html} = live_form(conn, "/admin/pages/update/#{c.page.id}")
        await_selector(view, "[data-block-uid]")
        selector = "#entry_block_form-#{c.block.uid}"
        params = view |> render() |> form_params(selector)
        var_id = hd(c.block.vars).id

        crafted =
          update_in(params, ["entry_block", "block", "vars"], fn _ ->
            %{"0" => %{"id" => to_string(var_id), "type" => "color", "key" => "renamed", "value" => @handler}}
          end)

        target = ["entry_block", "block", "vars", "0", "value"]
        view |> element(selector) |> render_change(Map.put(crafted, "_target", target))

        view |> form("#page_form_form") |> render_submit()
        assert_push_event(view, "b:submit", %{}, 5_000)
        view |> form("#page_form_form") |> render_submit()

        await(fn -> Repo.get!(Var, var_id).value == @handler end)
        assert %{type: :string, key: "title"} = Repo.get!(Var, var_id)

        [entry_block] = Repo.all(Brando.Pages.Page.Blocks) |> Enum.filter(&(&1.entry_id == c.page.id))
        block = Repo.preload(Repo.get!(Brando.Content.Block, entry_block.block_id), [:vars, :refs])
        html = Brando.Villain.parse([%{block: block}], Repo.get!(Brando.Pages.Page, c.page.id))

        refute html
               |> IO.iodata_to_binary()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("[onerror],script")
               |> Enum.any?()
      end
    end
  end
end
