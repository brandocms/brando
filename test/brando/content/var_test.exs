defmodule Brando.Content.VarTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Var

  test "video vars expose their asset association and config target" do
    changeset =
      Var.changeset(
        %Var{},
        %{
          type: :video,
          key: "hero_video",
          label: "Hero video",
          config_target: "video:Elixir.MyApp.Page:function:hero_video"
        },
        %{id: 1}
      )

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :type) == :video

    assert Ecto.Changeset.get_field(changeset, :config_target) ==
             "video:Elixir.MyApp.Page:function:hero_video"

    assert Map.has_key?(%Var{}, :video_id)
    assert Map.has_key?(%Var{}, :video)
  end

  test "gallery vars keep allowed media and separate upload config targets" do
    changeset =
      Var.changeset(
        %Var{},
        %{
          type: :gallery,
          key: "media",
          label: "Media",
          gallery_allowed_types: [:image],
          gallery_image_config_target: "image:Elixir.MyApp.Page:function:gallery_image",
          gallery_video_config_target: "video:Elixir.MyApp.Page:function:gallery_video"
        },
        %{id: 1}
      )

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :type) == :gallery
    assert Ecto.Changeset.get_field(changeset, :gallery_allowed_types) == [:image]
    assert Ecto.Changeset.get_field(changeset, :gallery_image_config_target) =~ "gallery_image"
    assert Ecto.Changeset.get_field(changeset, :gallery_video_config_target) =~ "gallery_video"
    assert Map.has_key?(%Var{}, :gallery_id)
    assert Map.has_key?(%Var{}, :gallery)
  end

  test "gallery vars default to both image and video" do
    changeset =
      Var.changeset(
        %Var{},
        %{type: :gallery, key: "media", label: "Media"},
        %{id: 1}
      )

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :gallery_allowed_types) == [:image, :video]
  end

  test "canonical var preloads include video and gallery media" do
    assert {:video, [:thumbnail, :file]} in Var.preloads()

    assert {:gallery, [gallery_objects: [:image, video: [:thumbnail, :file]]]} in Var.preloads()
  end
end
