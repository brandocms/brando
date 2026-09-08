defmodule BrandoAdmin.Components.Form.Input.ChangeTrackingTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 2]
  alias Phoenix.Component
  require Phoenix.LiveViewTest
  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input.{RenderVar, Select, MultiSelect}
  alias BrandoAdmin.Components.Form.Input.Blocks.{PictureBlock, VideoBlock}
  alias Ecto.Changeset

  for type <- [:image, :file, :video, :gallery] do
    test "#{type} var follows nil, replacement and clear from the parent" do
      type = unquote(type)
      key = :"#{type}_id"
      user = Factory.insert(:random_user)
      assets = [insert_asset(type, user), insert_asset(type, user)]
      socket = Component.assign(%Phoenix.LiveView.Socket{}, :blueprint_schema_opts, [])

      Enum.reduce([nil | assets] ++ [nil], socket, fn asset, socket ->
        id = asset && asset.id
        var = struct(Brando.Content.Var, %{key => id, :type => type, :key => "media", :creator_id => user.id})
        form = to_form(Changeset.change(var), as: "var")
        [updated] = RenderVar.update_many([{%{id: "stable-var", var: form}, socket}])
        assert updated.assigns[key] == id
        assert updated.assigns.value_id == id
        assert updated.assigns.value == id
        assert (updated.assigns[type] && updated.assigns[type].id) == id
        updated
      end)
    end
  end

  test "color vars carry their resolved palette through both editor modes" do
    form =
      to_form(Changeset.change(%Brando.Content.Var{type: :color, key: "color", label: "Color", value: "#123456"}),
        as: "var"
      )

    for edit <- [false, true] do
      html = Phoenix.LiveViewTest.render_component(RenderVar, id: "color-var", var: form, edit: edit)
      assert html =~ "Brando.ColorPicker"
      assert html =~ "#123456"
    end
  end

  test "picture ref reconciles replacement and clear without losing same-ID processed metadata" do
    a = %Brando.Images.Image{id: 11, path: "old.jpg", formats: [:jpg]}
    b = %Brando.Images.Image{id: 22, path: "new.jpg", formats: [:jpg]}
    socket = %Phoenix.LiveView.Socket{}
    {:ok, socket} = PictureBlock.update(picture_assigns(a), socket)
    assert socket.assigns.file_name == "old.jpg"
    {:ok, socket} = PictureBlock.update(picture_assigns(b), socket)
    assert socket.assigns.image.id == 22
    assert socket.assigns.file_name == "new.jpg"

    processed = %{b | path: "processed.jpg"}
    {:ok, socket} = PictureBlock.update(%{event: "image_processed", image: processed}, socket)
    {:ok, socket} = PictureBlock.update(picture_assigns(b), socket)
    assert socket.assigns.image == processed
    assert socket.assigns.file_name == "processed.jpg"

    {:ok, socket} = PictureBlock.update(picture_assigns(nil), socket)
    assert socket.assigns.image == nil
    assert socket.assigns.file_name == nil
  end

  test "unchanged parent ref does not roll back an in-flight local picker result" do
    a = %Brando.Images.Image{id: 11, path: "old.jpg"}
    b = %Brando.Images.Image{id: 22, path: "picked.jpg"}
    {:ok, socket} = PictureBlock.update(picture_assigns(a), %Phoenix.LiveView.Socket{})
    socket = Component.assign(socket, :image, b)
    {:ok, socket} = PictureBlock.update(picture_assigns(a), socket)
    assert socket.assigns.image == b
    {:ok, socket} = PictureBlock.update(picture_assigns(b), socket)
    assert socket.assigns.image == b
  end

  test "video ref refreshes document, type and cover on replacement and clears all on removal" do
    a = %Brando.Videos.Video{id: 11, type: :youtube, thumbnail: %Brando.Images.Image{id: 31}}
    b = %Brando.Videos.Video{id: 22, type: :upload, thumbnail: %Brando.Images.Image{id: 32}}
    socket = Component.assign(%Phoenix.LiveView.Socket{}, :video_upload_strategy, :local)
    {:ok, socket} = VideoBlock.update(video_assigns(a), socket)
    {:ok, socket} = VideoBlock.update(video_assigns(b), socket)
    assert socket.assigns.video.id == 22
    assert socket.assigns.video_data.id == 22
    assert socket.assigns.type == :upload
    assert socket.assigns.cover_image_id == 32
    {:ok, socket} = VideoBlock.update(video_assigns(nil), socket)
    assert socket.assigns.video == nil
    assert socket.assigns.video_data == %{}
    assert socket.assigns.cover_image == nil
    assert socket.assigns.cover_image_id == nil
  end

  test "a parent acknowledgement preserves the local video cover's picker ID" do
    video = %Brando.Videos.Video{id: 11, type: :youtube, thumbnail: nil}
    props = video_assigns(video)
    {:ok, socket} = VideoBlock.update(props, %Phoenix.LiveView.Socket{})

    socket =
      socket |> Component.assign(:cover_image, %{path: "picked-cover.jpg"}) |> Component.assign(:cover_image_id, 44)

    data = %Brando.Villain.Blocks.VideoBlock.Data{
      cover_image: %Brando.Villain.Blocks.PictureBlock.Data{alt: "Picked cover"}
    }

    block = to_form(Changeset.change(%Brando.Villain.Blocks.VideoBlock{data: data}), as: "block")
    {:ok, socket} = VideoBlock.update(%{props | block: block}, socket)
    assert socket.assigns.cover_image_id == 44
    assert socket.assigns.cover_image.path == "picked-cover.jpg"
  end

  test "ref resolver follows the FK when an association is stale or unloaded" do
    stale = %Brando.Content.Ref{uid: "ref", image_id: 22, image: %Brando.Images.Image{id: 11}}
    image = %Brando.Images.Image{id: 22}
    fetch = fn 22 -> {:ok, image} end
    assert Block.resolve_ref_association(to_form(Changeset.change(stale), as: "ref"), :image, :image_id, fetch) == image
    unloaded = %Brando.Content.Ref{uid: "ref", image_id: 22}

    assert Block.resolve_ref_association(to_form(Changeset.change(unloaded), as: "ref"), :image, :image_id, fetch) ==
             image

    cleared = %{stale | image_id: nil}
    assert Block.resolve_ref_association(to_form(Changeset.change(cleared), as: "ref"), :image, :image_id, fetch) == nil
  end

  for component <- [Select, MultiSelect] do
    test "#{inspect(component)} refreshes literal options and runtime language tokens" do
      component = unquote(component)
      field = to_form(%{"choice" => "one"}, as: "entry")[:choice]

      socket =
        Component.assign(%Phoenix.LiveView.Socket{}, :field, field)
        |> Component.assign(:opts, options: [%{label: "Old", value: "one"}])

      socket = component.assign_input_options(socket)
      socket = Component.assign(socket, :opts, options: [%{label: "New", value: "one"}, %{label: "Two", value: "two"}])
      socket = component.assign_input_options(socket)
      assert Enum.map(socket.assigns.input_options, & &1.label) == ["New", "Two"]
      previous = Brando.config(:languages)
      on_exit(fn -> Application.put_env(:brando, :languages, previous) end)
      socket = component.assign_input_options(Component.assign(socket, :opts, options: :languages))
      Application.put_env(:brando, :languages, [[value: "zz", text: "Updated language"]])
      socket = component.assign_input_options(socket)
      assert socket.assigns.input_options == [%{label: "Updated language", value: "zz"}]
    end

    test "#{inspect(component)} reloads callable options only for declared dependencies" do
      component = unquote(component)

      provider = fn form, _opts ->
        send(self(), {:options_loaded, form[:language].value})
        [%{label: form[:language].value, value: "one"}]
      end

      form = to_form(%{"choice" => "one", "language" => "en", "title" => "Old"}, as: "entry")

      socket =
        Component.assign(%Phoenix.LiveView.Socket{}, :field, form[:choice])
        |> Component.assign(:opts, options: provider, options_depends_on: [:language])

      socket = component.assign_input_options(socket)
      assert_receive {:options_loaded, "en"}
      changed = to_form(%{"choice" => "one", "language" => "en", "title" => "New"}, as: "entry")
      socket = component.assign_input_options(Component.assign(socket, :field, changed[:choice]))
      refute_receive {:options_loaded, _}
      changed = to_form(%{"choice" => "one", "language" => "no", "title" => "New"}, as: "entry")
      socket = component.assign_input_options(Component.assign(socket, :field, changed[:choice]))
      assert_receive {:options_loaded, "no"}
      assert hd(socket.assigns.input_options).label == "no"
    end
  end

  test "MultiSelect follows parent selections and options while retaining its open state" do
    make_field = fn values ->
      to_form(Changeset.change(%Brando.Content.Var{link_identifier_schemas: values}), as: "var")[:link_identifier_schemas]
    end

    props = %{id: "multi", field: make_field.(["one"]), opts: [options: [%{label: "One", value: "one"}]]}
    {:ok, socket} = MultiSelect.mount(%Phoenix.LiveView.Socket{})
    {:ok, socket} = MultiSelect.update(props, socket)
    socket = Component.assign(socket, :open, true)
    props = %{props | field: make_field.(["two"]), opts: [options: [%{label: "Two", value: "two"}]]}
    {:ok, socket} = MultiSelect.update(props, socket)
    assert socket.assigns.selected_options == ["two"]
    assert socket.assigns.selected_options_structs == ["two"]
    assert socket.assigns.input_options == [%{label: "Two", value: "two"}]
    assert socket.assigns.invalid_options == []
    assert socket.assigns.open
  end

  test "Select updates its label and parent options while preserving local open state" do
    field = to_form(Changeset.change(%Brando.Pages.Page{title: "one"}), as: "entry")[:title]
    props = %{id: "select", field: field, opts: [options: [%{label: "Old", value: "one"}], inline: false], inline: true}
    {:ok, socket} = Select.mount(%Phoenix.LiveView.Socket{})
    {:ok, socket} = Select.update(props, socket)
    assert socket.assigns.select_label == "Old"
    assert socket.assigns.inline
    socket = Component.assign(socket, :open, true)
    props = %{props | opts: [options: [%{label: "New", value: "one"}], inline: false]} |> Map.delete(:inline)
    {:ok, socket} = Select.update(props, socket)
    assert socket.assigns.select_label == "New"
    assert socket.assigns.open
    refute socket.assigns.inline
    assert socket.assigns.initial_run == false
  end

  test "Select explicit provider refresh also refreshes the displayed label" do
    field = to_form(Changeset.change(%Brando.Pages.Page{title: "one"}), as: "entry")[:title]
    provider = fn _, _ -> [%{label: Process.get(:option_label), value: "one"}] end
    props = %{id: "select", field: field, opts: [options: provider]}
    Process.put(:option_label, "Old")
    {:ok, socket} = Select.mount(%Phoenix.LiveView.Socket{})
    {:ok, socket} = Select.update(props, socket)
    Process.put(:option_label, "Refreshed")
    {:ok, socket} = Select.update(%{action: :force_refresh_options}, socket)
    assert socket.assigns.select_label == "Refreshed"
  end

  defp picture_assigns(image) do
    block = %Brando.Villain.Blocks.PictureBlock{data: %Brando.Villain.Blocks.PictureBlock.Data{}}
    ref = %Brando.Content.Ref{uid: "picture-ref", image_id: image && image.id, image: image}

    %{
      block: to_form(Changeset.change(block), as: "block"),
      ref_form: to_form(Changeset.change(ref), as: "ref"),
      form_id: "page_form"
    }
  end

  defp video_assigns(video) do
    block = %Brando.Villain.Blocks.VideoBlock{data: %Brando.Villain.Blocks.VideoBlock.Data{}}
    ref = %Brando.Content.Ref{uid: "video-ref", video_id: video && video.id, video: video}
    %{block: to_form(Changeset.change(block), as: "block"), ref_form: to_form(Changeset.change(ref), as: "ref")}
  end

  defp insert_asset(:file, user),
    do: Brando.Repo.insert!(%Brando.Files.File{filename: "fixture.txt", creator_id: user.id})

  defp insert_asset(:gallery, _user), do: Factory.insert(:gallery)
  defp insert_asset(type, user), do: Factory.insert(type, creator: user)
end
