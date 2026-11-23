defmodule BrandoAdmin.Live.Content.ModuleMediaDropSettingsTest do
  # The module editor's media drop settings (#3491): a multi module with
  # children offers its children, then the chosen child's media, picture and
  # video refs, and says which one is wrong before it saves.
  use Brando.LiveCase

  @moduletag :capture_log

  alias Brando.Content.Module
  alias Brando.Repo

  defp create_module(user, attrs) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          Map.merge(
            %{
              name: %{"en" => "Row"},
              namespace: %{"en" => "Content"},
              help_text: %{},
              code: "{{ content }}",
              refs: [],
              vars: []
            },
            attrs
          )
        ),
        user
      )

    module
  end

  defp ref(name, type), do: %{name: name, uid: Brando.Utils.generate_uid(), data: %{type: type, data: %{}}}

  setup %{current_user: user} do
    row = create_module(user, %{name: %{"en" => "Image row"}, multi: true})

    create_module(user, %{
      name: %{"en" => "Image card"},
      uid: "image-card",
      parent_id: row.id,
      refs: [ref("photo", "picture"), ref("caption", "text")]
    })

    %{row: row}
  end

  defp open(conn, row) do
    {:ok, view, _html} = live(conn, "/admin/config/content/modules/update/#{row.id}")
    view
  end

  defp select_options(view, id) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.id == id)).assigns.opts[:options]
  end

  defp submit(view, params) do
    view |> form("#module_form-el form.main-form") |> render_submit(%{"module" => params})
  end

  test "offers the children, then the chosen child's media refs, and saves them", %{conn: conn, row: row} do
    view = open(conn, row)
    assert select_options(view, "module-media_drop_child") == [%{label: "Image card", value: "image-card"}]
    assert select_options(view, "module-media_drop_ref") == []

    view |> form("#module_form-el form.main-form") |> render_change(%{"module" => %{"media_drop_child" => "image-card"}})
    assert select_options(view, "module-media_drop_ref") == [%{label: "photo (picture)", value: "photo"}]

    submit(view, %{"media_drop_child" => "image-card", "media_drop_ref" => "photo"})
    assert %{media_drop_child: "image-card", media_drop_ref: "photo"} = Repo.get!(Module, row.id)
  end

  test "says which ref is wrong and does not save it", %{conn: conn, row: row} do
    view = open(conn, row)
    html = submit(view, %{"media_drop_child" => "image-card", "media_drop_ref" => "caption"})

    assert html =~ "ref caption of image-card is a text ref, not a media, picture or video ref"
    assert %{media_drop_child: nil} = Repo.get!(Module, row.id)
  end

  test "a module that is not multi offers none", %{conn: conn, current_user: user} do
    single = create_module(user, %{name: %{"en" => "Single"}})
    refute has_element?(open(conn, single), ~s([name="module[media_drop_child]"]))
  end
end
