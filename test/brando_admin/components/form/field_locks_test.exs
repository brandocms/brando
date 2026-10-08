defmodule BrandoAdmin.Components.Form.FieldLocksTest do
  # The field locks other editors see: the fields that take and release them
  # outside the text inputs (media drawers, multi-selects), and what a lock
  # costs. The two-editor flows are in `test/brando_admin/live/entry_field_sync_test.exs`.
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.FileDrawer
  alias BrandoAdmin.Components.Form.ImageDrawer
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.VideoDrawer
  alias Ecto.Changeset

  defp pushes?(%Phoenix.LiveView.JS{ops: ops}, event, target),
    do: Enum.any?(ops, &match?(["push", %{event: ^event, target: ^target}], &1))

  describe "a media drawer's close releases its field" do
    # Done, ×, the backdrop and Escape (the drawer's `data-modal-close`) all
    # run these, and so does the drawer's remove button.
    test "the image, video and file drawers send the form a blur" do
      for js <- [
            ImageDrawer.close_image(7),
            ImageDrawer.reset_image_field(7),
            VideoDrawer.close_video(7),
            VideoDrawer.reset_video_field(7),
            FileDrawer.close_file(7),
            FileDrawer.reset_file_field(7)
          ] do
        assert pushes?(js, "blur", 7)
      end
    end

    # The removal is pushed before the blur, so the blur ships it.
    test "a remove pushes the reset before the blur" do
      %{ops: ops} = ImageDrawer.reset_image_field(7)
      events = for ["push", %{event: event}] <- ops, do: event
      assert events == ["reset_image_field", "blur"]
    end
  end

  describe "opening a media field's drawer locks the field through the form" do
    test "a video field" do
      changeset =
        %Brando.Content.Ref{}
        |> Changeset.change(%{name: "video_ref", uid: "vidref0001"})
        |> Changeset.put_change(:video_id, nil)

      field = Phoenix.Component.to_form(changeset, as: :page)[:video]

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          field: field,
          relation_field: field.form[:video_id],
          video_id: nil,
          video: nil,
          myself: 3,
          defaults: %{}
        }
      }

      Input.Video.handle_event("open_video", %{}, socket)
      assert_received {:phoenix, :send_update, {{Form, _form_id}, %{event: "focus_field", field: "page[video]"}}}
    end

    test "a file field" do
      form = Phoenix.Component.to_form(Changeset.change(%Brando.Content.Ref{}), as: :page)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          field: form[:file],
          relation_field: form[:file_id],
          file_id: nil,
          file: nil,
          myself: 3,
          path: [],
          form_id: "page_form"
        }
      }

      Input.File.handle_event("open_file", %{}, socket)
      assert_received {:phoenix, :send_update, {{Form, "page_form"}, %{event: "focus_field", field: "page[file]"}}}
    end
  end

  defmodule Host do
    use Phoenix.LiveView, layout: false

    def mount(_, %{"user_id" => user_id}, socket) do
      var = %Brando.Content.Var{id: 4711, link_identifier_schemas: []}
      form = Phoenix.Component.to_form(Ecto.Changeset.change(var), as: "var")
      {:ok, Phoenix.Component.assign(socket, form: form, current_user: %Brando.Users.User{id: user_id})}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={BrandoAdmin.Components.Form.Input.MultiSelect}
        id="schemas"
        field={@form[:link_identifier_schemas]}
        label="Schemas"
        current_user={@current_user}
        opts={[options: [%{label: "Contact", value: "contact"}]]}
      />
      """
    end
  end

  test "a multi-select is locked while its options are open, and released when they close", %{conn: conn} do
    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("active_field", Brando.Content.Var, 4711))
    {:ok, view, _html} = live_isolated(conn, Host, session: %{"user_id" => 9})

    view |> element(".multiselect > .button-edit") |> render_click()
    assert_receive {:active_field, "var[link_identifier_schemas]", 9, _tab}

    view |> element("button.primary.small", "OK") |> render_click()
    assert_receive {:active_field, nil, 9, _tab}
  end

  test "locks belong to the tab, and a tab's id is the same for its components" do
    tab = BrandoAdmin.Presence.tab()
    assert tab == BrandoAdmin.Presence.tab()
    refute tab == Task.await(Task.async(&BrandoAdmin.Presence.tab/0))
  end
end
