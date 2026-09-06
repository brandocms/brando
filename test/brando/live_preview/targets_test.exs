defmodule Brando.LivePreview.TargetsTest do
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.LivePreview
  alias Brando.Pages.Page

  setup do
    entry = %Page{title: "Unsaved title", language: :en, entry_blocks: []} |> Map.put(:key, "about")
    {:ok, changeset: Ecto.Changeset.change(entry)}
  end

  test "legacy targets remain the default and named targets resolve without browser atom conversion" do
    assert LivePreview.get_target_config(Page).name == :default
    assert LivePreview.get_target_config(Page, "listing").label == "Listing"
    assert Enum.map(LivePreview.get_targets(Page), & &1.name) == [:default, :listing, :broken]

    assert_raise Brando.Exception.LivePreviewError, fn ->
      LivePreview.get_target_config(Page, "not-a-declared-target")
    end
  end

  test "names are unique within a schema, while different schemas can share a name" do
    module = Module.concat(__MODULE__, "Targets#{System.unique_integer([:positive])}")

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Brando.LivePreview

          preview_target Brando.Pages.Page do
            name :listing
          end

          preview_target Brando.Pages.Fragment do
            name :listing
          end
        end
      end
    )

    assert length(Spark.Dsl.Extension.get_entities(module, [:live_preview])) == 2

    assert_raise Spark.Error.DslError, ~r/Duplicate preview target/, fn ->
      Code.compile_quoted(
        quote do
          defmodule unquote(Module.concat(module, Duplicate)) do
            use Brando.LivePreview

            preview_target Brando.Pages.Page do
              name :listing
            end

            preview_target Brando.Pages.Page do
              name :listing
            end
          end
        end
      )
    end
  end

  test "switches retain the key, replace cached assigns, and apply to subsequent updates", %{changeset: changeset} do
    assert {:ok, key} = LivePreview.initialize(Page, changeset)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    assert LivePreview.target_name(key) == :default
    assert {:ok, html} = LivePreview.get_cache(key)
    assert html =~ "Hi Todd"
    Brando.endpoint().subscribe("live_preview:#{key}")

    assert {:ok, ^key} = LivePreview.switch_target(Page, changeset, key, "listing")
    assert_receive %Phoenix.Socket.Broadcast{event: "reload"}
    assert LivePreview.target_name(key) == :listing
    assert LivePreview.get_var(key, :employees) == [%{id: nil, name: "Unsaved title"}]
    assert {:ok, html} = LivePreview.get_cache(key)
    assert html =~ ~s(data-preview="listing")
    assert html =~ "Unsaved title"
    refute html =~ "Todd"

    changed = Ecto.Changeset.put_change(changeset, :title, "Another edit")
    LivePreview.invalidate_var(key, :employees)
    assert ^key = LivePreview.reload(Page, changed, key)
    assert {:ok, html} = LivePreview.get_cache(key)
    assert html =~ "Another edit"
    assert LivePreview.target_name(key) == :listing

    assert {:ok, ^key} = LivePreview.switch_target(Page, changed, key, :default)
    assert {:ok, html} = LivePreview.get_cache(key)
    assert html =~ "Hi Todd"
  end

  test "failed and unknown switches preserve the previous view and target", %{changeset: changeset} do
    assert {:ok, key} = LivePreview.initialize(Page, changeset, %{}, :listing)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    assert {:ok, before_html} = LivePreview.get_cache(key)

    for target <- [:broken, "unknown"] do
      capture_log(fn -> assert {:error, _} = LivePreview.switch_target(Page, changeset, key, target) end)
      assert LivePreview.target_name(key) == :listing
      assert {:ok, ^before_html} = LivePreview.get_cache(key)
    end

    assert ^key = LivePreview.update_cache(key, Page, changeset)
    assert {:ok, ^before_html} = LivePreview.get_cache(key)
  end

  test "independent editors do not share their selected view or assigns", %{changeset: changeset} do
    assert {:ok, first} = LivePreview.initialize(Page, changeset)
    assert {:ok, second} = LivePreview.initialize(Page, changeset, %{}, :listing)
    on_exit(fn -> Enum.each([first, second], &LivePreview.cleanup_cache/1) end)
    assert {:ok, _} = LivePreview.switch_target(Page, changeset, first, :listing)
    assert {:ok, _} = LivePreview.switch_target(Page, changeset, first, :default)
    assert LivePreview.target_name(second) == :listing
    assert LivePreview.get_var(second, :employees) == [%{id: nil, name: "Unsaved title"}]

    {:ok, cleanup} = LivePreview.cleanup_cache(second)
    monitor = Process.monitor(cleanup)
    assert_receive {:DOWN, ^monitor, :process, ^cleanup, _reason}
    assert LivePreview.target_name(second) == nil
    assert LivePreview.get_cache(second) == {:ok, nil}
    assert LivePreview.get_var(second, :employees) == :not_set
  end

  test "non-block forms switch synchronously and recovery restores the server-owned target", %{changeset: changeset} do
    assert {:ok, key} = LivePreview.initialize(Page, changeset)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)

    socket =
      Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, %{
        id: "page_form",
        form: Phoenix.Component.to_form(changeset),
        schema: Page,
        live_preview_targets: LivePreview.get_targets(Page),
        live_preview_schema_target: nil,
        live_preview_cache_key: key,
        live_preview_active?: true,
        live_preview_menu_open?: true,
        pending_live_preview_target: nil,
        updated_entry_assocs: %{},
        has_blocks?: false,
        block_map: [],
        block_changesets: %{},
        form_blueprint: %{blocks: []}
      })

    assert {:noreply, ^socket} =
             BrandoAdmin.Components.Form.handle_event("select_preview_target", %{"name" => "unknown"}, socket)

    assert {:noreply, switched} =
             BrandoAdmin.Components.Form.handle_event("select_preview_target", %{"name" => "listing"}, socket)

    assert switched.assigns.live_preview_schema_target == :listing
    assert switched.assigns.fields_demanding_live_preview_reassign == [{:employees, [:title]}]
    refute switched.assigns.live_preview_menu_open?

    # A reconnect has no selected target in its fresh socket. Only the cache
    # key is recovered from the DOM; target selection comes from server state.
    recovering = Phoenix.Component.assign(socket, live_preview_active?: false, form_recovered?: false)

    assert {:noreply, recovered} =
             BrandoAdmin.Components.Form.handle_event(
               "recover_live_preview_state",
               %{"live_preview" => %{"cache_key" => key}},
               recovering
             )

    assert recovered.assigns.live_preview_schema_target == :listing
    assert recovered.assigns.live_preview_recovery_pending?
    assert recovered.assigns.fields_demanding_live_preview_reassign == [{:employees, [:title]}]
  end

  test "sharing renders the selected target as an independent snapshot", %{changeset: changeset} do
    user = Brando.Factory.insert(:random_user, avatar: nil)
    assert {:ok, url, _days} = LivePreview.share(Page, changeset, user, %{}, :listing)
    preview = Repo.one!(Brando.Sites.Preview)
    assert url =~ preview.preview_key
    html = Brando.Utils.binary_to_term(preview.html)
    assert html =~ ~s(data-preview="listing")
    assert html =~ "Unsaved title"
  end
end
