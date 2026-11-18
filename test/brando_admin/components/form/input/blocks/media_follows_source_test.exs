defmodule BrandoAdmin.Components.Form.Input.Blocks.MediaFollowsSourceTest do
  # In a synchronized translation media in blocks follows the source
  # (guides/i18n.md). Every control that changes a ref's or a variable's media
  # carries `media-source-control`, which Blocks.css hides under the block
  # field's `.is-source-locked`, and `MediaField.source_note/1` shows in their
  # place. The markup is the same in the source and the translation: these
  # tests drop what the stylesheet hides to see what a translator gets, and
  # check that the source keeps every control. Configure stays in both: a
  # use's caption, alt text and file title are the translation's own.
  use Brando.ConnCase, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2, rendered_to_string: 1]

  alias Brando.Factory
  alias Brando.Villain.Blocks.FileBlock, as: FileData
  alias Brando.Villain.Blocks.GalleryBlock, as: GalleryData
  alias Brando.Villain.Blocks.PictureBlock, as: PictureData
  alias Brando.Villain.Blocks.VideoBlock, as: VideoData
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias Ecto.Changeset

  @note "Media follows the source; choose it there."
  @empty_note "No media chosen in the source. " <> @note

  defp ref_forms(ref, data) do
    ref = %{ref | uid: ref.uid || "ref-uid", name: ref.name || "media"}
    {to_form(Changeset.change(ref), as: "block[refs][0]"), to_form(Changeset.change(data), as: "block[refs][0][data]")}
  end

  defp render_ref(module, ref, data, extra \\ []) do
    {ref_form, block} = ref_forms(ref, data)

    module
    |> render_component(
      [
        id: "#{ref_form[:uid].value}-ref",
        block: block,
        ref_form: ref_form,
        ref_name: ref.name,
        ref_description: nil,
        config_open: nil,
        target: nil,
        target_ref: {BrandoAdmin.Components.Form.Block, "block-1"},
        form_id: "entry_form"
      ] ++ extra
    )
    |> Floki.parse_fragment!()
  end

  # What a synchronized translation shows: the stylesheet hides every
  # `media-source-control`.
  defp in_translation(doc), do: Floki.filter_out(doc, ".media-source-control")

  # The names of the buttons in the ref's body (not its toolbar) or in the
  # given part of the document
  defp buttons(doc, scope \\ ".block-content") do
    doc
    |> Floki.find("#{scope} button")
    |> Enum.map(fn button ->
      case Floki.find(button, ".media-button-label") do
        [] -> button |> Floki.text() |> String.trim()
        label -> label |> Floki.text() |> String.trim()
      end
    end)
    |> Enum.map(fn
      "" -> :icon
      name -> name
    end)
  end

  defp notes(doc), do: doc |> Floki.find(".media-source-note") |> Enum.map(&(&1 |> Floki.text() |> squish()))
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp image do
    Factory.insert(:image, status: :processed, path: "images/a.jpg", width: 10, height: 10)
  end

  describe "a picture ref" do
    test "with an image: only Configure in a translation, every control in the source" do
      image = image()

      doc =
        render_ref(Blocks.PictureBlock, %Brando.Content.Ref{image_id: image.id, image: image}, %PictureData{
          type: "picture",
          data: %PictureData.Data{}
        })

      assert "Remove" in buttons(doc) and "Replace" in buttons(doc) and "Edit/Crop" in buttons(doc)
      assert buttons(in_translation(doc)) == ["Configure"]
      assert notes(doc) == [@note]
    end

    test "empty: no controls and the empty note in a translation" do
      doc =
        render_ref(Blocks.PictureBlock, %Brando.Content.Ref{}, %PictureData{type: "picture", data: %PictureData.Data{}})

      assert "Upload" in buttons(doc)
      assert buttons(in_translation(doc)) == []
      assert notes(doc) == [@empty_note]
      # "Drop an image here" is not what a translator can do
      refute doc |> in_translation() |> Floki.find(".media-field-copy") |> Floki.text() =~ "Drop an image here"
    end

    test "its settings keep the caption and alt text, but not the image's controls" do
      image = image()
      ref = %Brando.Content.Ref{uid: "pic", name: "pic", image_id: image.id, image: image}

      doc =
        render_ref(Blocks.PictureBlock, ref, %PictureData{type: "picture", data: %PictureData.Data{}}, config_open: "pic")

      translation = in_translation(doc)

      assert Floki.find(translation, ~s([name$="[data][title]"])) != []
      assert Floki.find(translation, ~s([name$="[data][alt]"])) != []
      # The "Image" section shows the image and the note, nothing to change it with
      assert buttons(translation, "[id$='-panel-image']") == []
      assert "Replace" in buttons(doc, "[id$='-panel-image']")
      refute translation |> Floki.text() =~ "Replace the image"
    end
  end

  describe "a file ref" do
    test "with a file: only Configure in a translation" do
      file = Brando.Repo.insert!(%Brando.Files.File{filename: "guide.pdf", filesize: 1, config_target: "default"})

      doc =
        render_ref(Blocks.FileBlock, %Brando.Content.Ref{file_id: file.id, file: file}, %FileData{
          type: "file",
          data: %FileData.Data{}
        })

      assert "Replace" in buttons(doc) and "Remove" in buttons(doc)
      assert buttons(in_translation(doc)) == ["Configure"]
      assert notes(doc) == [@note]
    end

    test "its settings keep the title, link label and description" do
      file = Brando.Repo.insert!(%Brando.Files.File{filename: "guide.pdf", filesize: 1, config_target: "default"})
      ref = %Brando.Content.Ref{uid: "doc", name: "doc", file_id: file.id, file: file}
      doc = render_ref(Blocks.FileBlock, ref, %FileData{type: "file", data: %FileData.Data{}}, config_open: "doc")
      translation = in_translation(doc)

      for field <- ~w(title label description) do
        assert Floki.find(translation, ~s([name$="[data][#{field}]"])) != [], field
      end

      assert buttons(translation, "[id$='-panel-file']") == []
    end
  end

  describe "a video ref" do
    test "with a video: only Configure in a translation" do
      video = Factory.insert(:external_file_video)

      doc =
        render_ref(Blocks.VideoBlock, %Brando.Content.Ref{video_id: video.id, video: video}, %VideoData{
          type: "video",
          data: %VideoData.Data{}
        })

      assert "Replace" in buttons(doc) and "Remove" in buttons(doc)
      assert buttons(in_translation(doc)) == ["Configure"]
      assert notes(doc) == [@note]
    end
  end

  describe "a gallery ref" do
    setup do
      image = image()
      gallery = Factory.insert(:gallery)
      Factory.insert(:gallery_object, gallery_id: gallery.id, image_id: image.id, sequence: 0)
      gallery = Brando.Repo.preload(gallery, [gallery_objects: [:image, video: [:thumbnail]]], force: true)
      %{gallery: gallery}
    end

    test "keeps each item's settings and texts, but nothing that adds, removes or edits media", %{gallery: gallery} do
      ref = %Brando.Content.Ref{gallery_id: gallery.id, gallery: gallery}
      doc = render_ref(Blocks.GalleryBlock, ref, %GalleryData{type: "gallery", data: %GalleryData.Data{type: :gallery}})
      translation = in_translation(doc)

      assert "Upload" in buttons(doc)
      assert Floki.find(doc, ".gallery-object .delete-x") != []
      assert Floki.find(doc, ".gallery-object .edit-image-btn") != []

      refute "Upload" in buttons(translation)
      assert Floki.find(translation, ".gallery-object .delete-x, .gallery-object .edit-image-btn") == []
      # The item's settings (its captions) and the caption and alt editors stay
      assert Floki.find(translation, ".gallery-object .configure-object") != []
      assert notes(doc) == [@note]
    end

    test "empty: the empty note instead of the drop invitation" do
      doc =
        render_ref(Blocks.GalleryBlock, %Brando.Content.Ref{}, %GalleryData{
          type: "gallery",
          data: %GalleryData.Data{type: :gallery}
        })

      translation = in_translation(doc)
      assert buttons(translation) == []
      assert notes(doc) == [@empty_note]
      refute Floki.text(translation) =~ "Drop media here"
    end
  end

  describe "media variables" do
    defp render_var(type, assoc, value) do
      var = %Brando.Content.Var{id: 7, key: "hero", type: type, label: %{"en" => "Hero"}}
      form = to_form(Changeset.change(var), as: "block[vars][0]")

      %{
        __changed__: nil,
        type: type,
        var: form,
        label: "Hero",
        instructions: nil,
        edit: false,
        upload_kind: "block_var",
        component_id: "var-7",
        var_key: "hero",
        target: nil,
        provider_hook: nil,
        image_id: nil,
        file_id: nil,
        video_id: nil,
        gallery_id: nil,
        image: nil,
        file: nil,
        video: nil,
        gallery: nil
      }
      |> Map.put(assoc, value)
      |> RenderVar.render_value_inputs()
      |> rendered_to_string()
      |> Floki.parse_fragment!()
    end

    test "an image, a file and a video variable: nothing to change in a translation" do
      file = Brando.Repo.insert!(%Brando.Files.File{filename: "guide.pdf", filesize: 1, config_target: "default"})

      for {type, assoc, value} <- [
            {:image, :image, image()},
            {:file, :file, file},
            {:video, :video, Factory.insert(:external_file_video)}
          ] do
        doc = render_var(type, assoc, value)
        assert "Change" in buttons(doc, ".media-field--line"), inspect(type)
        assert buttons(in_translation(doc), ".media-field--line") == [], inspect(type)
        assert doc |> Floki.find(".media-field--line .media-source-note") |> Enum.map(&squish(Floki.text(&1))) == [@note]
      end
    end

    test "a gallery variable: nothing to change in a translation" do
      doc = render_var(:gallery, :gallery, %Brando.Galleries.Gallery{gallery_objects: []})

      # The gallery's row; its settings dialog opens only from the row's menu
      row = "[id$='-gallery-media']"
      assert "Add" in buttons(doc, row)
      assert buttons(in_translation(doc), row) == []

      assert doc
             |> Floki.find(".media-gallery > .media-field-copy .media-source-note")
             |> Enum.map(&squish(Floki.text(&1))) == [@empty_note]

      refute doc |> in_translation() |> Floki.find(".media-gallery > .media-field-copy") |> Floki.text() =~ "Drop media"
    end
  end
end
