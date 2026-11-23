defmodule Brando.Content.ModuleMediaDropTest do
  @moduledoc """
  A multi module's `media_drop`: the child module each file dropped on its
  blocks becomes, and the ref the file goes in. It is checked in the module
  editor and in definition files, goes with duplication, the module export
  and the definition files, and builds the child block for a dropped file.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Content.{Blocks, Definitions, Module, ModuleDiff}
  alias Brando.Villain.Blocks.{MediaBlock, PictureBlock, VideoBlock}
  alias Brando.{Factory, Repo}

  import Ecto.Query, only: [from: 2]

  defp create_module(user, attrs) do
    {:ok, module} =
      %{
        name: %{"en" => "Card"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Card"},
        class: "card-#{System.unique_integer([:positive])}",
        code: "{% ref refs.body %}",
        refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Text"}}}]
      }
      |> Map.merge(attrs)
      |> Content.create_module(user)

    module
  end

  defp ref(name, type, data \\ %{}),
    do: %{name: name, uid: Brando.Utils.generate_uid(), data: %{type: type, data: data}}

  # An image row: a multi module whose child cards have a picture, a media and
  # a text ref
  defp image_row(user, attrs \\ %{}) do
    row = create_module(user, Map.merge(%{class: "image-row", multi: true, uid: "image-row"}, attrs))

    card =
      create_module(user, %{
        class: "image-card",
        uid: "image-card",
        parent_id: row.id,
        sequence: 0,
        refs: [
          ref("photo", "picture"),
          ref("visual", "media", %{
            available_blocks: ["picture", "video"],
            template_picture: %{img_class: "from-template"},
            template_video: %{autoplay: true}
          }),
          ref("body", "text", %{text: "Text"})
        ]
      })

    {row, card}
  end

  defp editor_module(row) do
    children = from(c in Module, where: is_nil(c.deleted_at), order_by: [asc: c.sequence, asc: c.id])
    Repo.preload(Repo.get!(Module, row.id), [:vars, :refs, children: {children, [:refs]}])
  end

  defp errors(changeset), do: Enum.map(changeset.errors, fn {field, {message, keys}} -> {field, message, keys} end)

  setup do
    %{user: Factory.insert(:random_user)}
  end

  describe "in the module editor" do
    test "names a child module and one of its media, picture or video refs", %{user: user} do
      {row, _card} = image_row(user)

      for ref <- ~w(photo visual) do
        changeset = Module.changeset(editor_module(row), %{media_drop_child: "image-card", media_drop_ref: ref}, user)
        assert changeset.valid?, inspect(changeset.errors)
      end

      {:ok, saved} =
        row
        |> editor_module()
        |> Module.changeset(%{media_drop_child: "image-card", media_drop_ref: "photo"}, user)
        |> Repo.update()

      assert {saved.media_drop_child, saved.media_drop_ref} == {"image-card", "photo"}
      assert saved.version == row.version + 1
      assert ModuleDiff.classify(ModuleDiff.diff(row, saved)) == :metadata
    end

    test "says which child or ref is wrong", %{user: user} do
      {row, _card} = image_row(user)
      module = editor_module(row)

      assert [{:media_drop_child, "%{child} is not a child module of this module", [child: "quote-card"]}] =
               errors(Module.changeset(module, %{media_drop_child: "quote-card", media_drop_ref: "photo"}, user))

      assert [{:media_drop_ref, "%{child} has no ref %{ref}", [child: "image-card", ref: "cover"]}] =
               errors(Module.changeset(module, %{media_drop_child: "image-card", media_drop_ref: "cover"}, user))

      assert [{:media_drop_ref, _message, [child: "image-card", ref: "body", type: "text"]}] =
               errors(Module.changeset(module, %{media_drop_child: "image-card", media_drop_ref: "body"}, user))

      assert [{:media_drop_ref, _message, [child: "image-card"]}] =
               errors(Module.changeset(module, %{media_drop_child: "image-card"}, user))

      assert [{:media_drop_child, _message, []}] = errors(Module.changeset(module, %{media_drop_ref: "photo"}, user))
    end

    test "needs a multi module", %{user: user} do
      {row, _card} = image_row(user)

      assert [{:media_drop_child, "needs a multi module", []}] =
               errors(
                 Module.changeset(
                   editor_module(row),
                   %{multi: false, media_drop_child: "image-card", media_drop_ref: "photo"},
                   user
                 )
               )
    end

    test "cleared, both go", %{user: user} do
      {row, _card} = image_row(user, %{media_drop_child: "image-card", media_drop_ref: "photo"})
      changeset = Module.changeset(editor_module(row), %{media_drop_child: "", media_drop_ref: ""}, user)

      assert changeset.valid?
      assert {:ok, %{media_drop_child: nil, media_drop_ref: nil}} = Repo.update(changeset)
    end
  end

  test "a duplicate names its own copy of the child", %{user: user} do
    {row, card} = image_row(user, %{media_drop_child: "image-card", media_drop_ref: "photo"})

    {:ok, copy} = Content.duplicate_module(row.id, user)
    copy = Repo.preload(Repo.get!(Module, copy.id), :children)

    assert [copied_card] = copy.children
    refute copied_card.uid == card.uid
    assert {copy.media_drop_child, copy.media_drop_ref} == {copied_card.uid, "photo"}
    assert Repo.get!(Module, row.id).media_drop_child == "image-card"
  end

  test "the module export names the exported copy of the child", %{user: user} do
    {row, _card} = image_row(user, %{media_drop_child: "image-card", media_drop_ref: "photo"})

    [exported] =
      %{filter: %{ids: [row.id]}, preload: [:vars, :refs, children: [:vars, :refs]]}
      |> Content.list_modules!()
      |> Content.prepare_modules_for_export(user.id)

    assert [card] = exported.children
    refute card.uid == "image-card"
    assert {exported.media_drop_child, exported.media_drop_ref} == {card.uid, "photo"}
  end

  describe "definition files" do
    setup do
      directory = Path.join(System.tmp_dir!(), "brando-media-drop-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(directory) end)
      %{directory: directory}
    end

    test "carry it, and a second import of the export is a noop", %{user: user, directory: directory} do
      image_row(user, %{media_drop_child: "image-card", media_drop_ref: "visual"})

      assert {:ok, exported} = Definitions.export(directory, user, uids: ["image-row"])
      sources = for file <- exported.files, String.ends_with?(file, ".exs"), do: File.read!(Path.join(directory, file))
      assert Enum.any?(sources, &(&1 =~ ~s(\n  media_drop child: "image-card", ref: "visual"\n)))

      assert {:ok, bundle} = Definitions.read(directory)
      assert %{"media_drop_child" => "image-card", "media_drop_ref" => "visual"} = row_definition(bundle)
      assert %{"media_drop_child" => nil, "media_drop_ref" => nil} = definition(bundle, "image-card")
      assert {:ok, %{items: items}} = Definitions.plan(bundle, user)
      assert Enum.all?(items, &(&1.action == :noop))

      # Changed in the file, it changes in the module
      changed = put_in(bundle, ["modules", Access.filter(&(&1["uid"] == "image-row")), "media_drop_ref"], "photo")
      assert {:ok, plan} = Definitions.plan(changed, user)
      assert {:ok, _} = Definitions.apply(plan, user)
      assert Repo.get_by!(Module, uid: "image-row").media_drop_ref == "photo"
    end

    test "are refused with a message naming a child the module does not have, or a ref that is no media ref",
         %{directory: directory} do
      write_row!(directory, ~s(media_drop child: "quote-card", ref: :photo))
      assert {:error, message} = Definitions.read(directory)
      assert message =~ "media_drop"
      assert message =~ "quote-card is not a child module of this module"

      File.rm_rf!(directory)
      write_row!(directory, ~s(media_drop child: "image-card", ref: :body))
      assert {:error, message} = Definitions.read(directory)
      assert message =~ "ref body of image-card is a text ref, not a media, picture or video ref"

      File.rm_rf!(directory)
      write_row!(directory, ~s(media_drop child: "image-card", ref: :cover))
      assert {:error, message} = Definitions.read(directory)
      assert message =~ "image-card has no ref cover"
    end

    test "read the child as a module name too", %{directory: directory} do
      write_row!(directory, ~s(media_drop child: Example.ImageCard, ref: :photo))
      assert {:ok, bundle} = Definitions.read(directory)
      assert %{"media_drop_child" => "image-card", "media_drop_ref" => "photo"} = row_definition(bundle)
    end
  end

  defp definition(bundle, uid), do: Enum.find(bundle["modules"], &(&1["uid"] == uid))
  defp row_definition(bundle), do: definition(bundle, "image-row")

  defp write_row!(directory, media_drop) do
    File.mkdir_p!(Path.join(directory, "image-row"))

    File.write!(Path.join(directory, "image-row.exs"), """
    defmodule Example.ImageRow do
      use Brando.Content.Definition
      uid "image-row"
      name en: "Image row"
      class "image-row"
      multi true
      #{media_drop}

      children do
        child "image-card"
      end

      template :liquid, "{{ content }}"
    end
    """)

    File.write!(Path.join(directory, "image-row/image-card.exs"), """
    defmodule Example.ImageCard do
      use Brando.Content.Definition
      uid "image-card"
      name en: "Image card"
      class "image-card"

      refs do
        ref :photo, :picture
        ref :body, :text
      end

      template :liquid, "{% ref refs.photo %}"
    end
    """)
  end

  describe "the block for a dropped file" do
    test "a media ref becomes a picture or a video with the ref's template for it", %{user: user} do
      {_row, card} = image_row(user)

      for {kind, struct, field, value} <- [
            {:image, PictureBlock, :img_class, "from-template"},
            {:video, VideoBlock, :autoplay, true}
          ] do
        block_cs = Blocks.build_media_drop_block(card.id, "visual", kind, user.id, Brando.Pages.Page.Blocks)

        assert Ecto.Changeset.get_field(block_cs, :type) == :module_entry
        assert Ecto.Changeset.get_field(block_cs, :module_id) == card.id
        refs = Map.new(Ecto.Changeset.get_assoc(block_cs, :refs, :struct), &{&1.name, &1.data})
        assert %^struct{} = refs["visual"]
        assert Map.fetch!(refs["visual"].data, field) == value
        assert %PictureBlock{} = refs["photo"]
      end
    end

    test "a picture ref stays as it is", %{user: user} do
      {_row, card} = image_row(user)
      block_cs = Blocks.build_media_drop_block(card.id, "photo", :image, user.id, Brando.Pages.Page.Blocks)
      refs = Map.new(Ecto.Changeset.get_assoc(block_cs, :refs, :struct), &{&1.name, &1.data})

      assert %PictureBlock{} = refs["photo"]
      assert %MediaBlock{} = refs["visual"]
    end
  end
end
