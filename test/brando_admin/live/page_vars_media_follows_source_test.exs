defmodule BrandoAdmin.PageVarsMediaFollowsSourceTest do
  # A page's own variables follow the source like a block's: in a
  # synchronized translation their media is the source's. Each variable
  # carries `.is-source-locked` there (`RenderVar`), under which Blocks.css
  # hides every `media-source-control` and shows the "Media follows the
  # source" note. These tests drop what the stylesheet hides to see what a
  # translator gets. Text variables stay editable, and the source keeps
  # every control. (`MediaFollowsSourceTest` covers block refs and
  # variables.) Not async: `put_test_env(Page, …)` sets the application's
  # Page configuration, which tests beside it would see.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Var
  alias Brando.Galleries.{Gallery, GalleryObject}
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Translations

  @note "Media follows the source; choose it there."

  setup %{current_user: user} do
    put_test_env(Page, translatable: [mode: :synchronized])
    image = Factory.insert(:image, creator: user, status: :processed)
    video = Factory.insert(:video)
    file = Repo.insert!(%Brando.Files.File{filename: "guide.pdf", filesize: 1, config_target: "default"})

    gallery =
      Repo.insert!(%Gallery{config_target: "default", gallery_objects: [%GalleryObject{image_id: image.id, sequence: 0}]})

    source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: user)

    for {attrs, sequence} <-
          Enum.with_index([
            %{type: :image, key: "portrait", image_id: image.id},
            %{type: :file, key: "brochure", file_id: file.id},
            %{type: :video, key: "clip", video_id: video.id},
            %{type: :gallery, key: "album", gallery_id: gallery.id},
            %{type: :image, key: "empty_image"},
            %{type: :string, key: "tagline", value: "Hei"}
          ]) do
      Repo.insert!(struct(Var, Map.merge(attrs, %{label: %{"en" => attrs.key}, page_id: source.id, sequence: sequence})))
    end

    {:ok, target} = Translations.create_target(Page, source.id, :en, user)
    %{source: source, target: target}
  end

  defp open(conn, id) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{id}")
    await_selector(view, "#page_form_form")
    view
  end

  # The page's own variables, by key (`RenderVar` marks its root with the
  # var's id)
  defp page_vars(view, page) do
    doc = view |> render() |> Floki.parse_document!()
    ids = Repo.all(from(v in Var, where: v.page_id == ^page.id, select: {v.key, v.id}))

    Map.new(ids, fn {key, id} ->
      {key, doc |> Floki.find(~s(#page_form_form .variable[data-id="#{id}"])) |> List.first()}
    end)
  end

  # What a synchronized translation shows: the stylesheet hides every
  # `media-source-control` under `.is-source-locked`.
  defp as_shown(variable) do
    if locked?(variable), do: Floki.filter_out(variable, ".media-source-control"), else: variable
  end

  defp locked?({_tag, attrs, _children}),
    do: attrs |> List.keyfind("class", 0, {"class", ""}) |> elem(1) |> String.split() |> Enum.member?("is-source-locked")

  # The buttons of the variable's media field (an image's, file's or video's)
  # or of the gallery's row. (The rest of the editor is the variable's
  # definition, which superusers edit.)
  defp buttons(variable) do
    variable
    |> Floki.find("[id$='-media'] button")
    |> Enum.map(&(&1 |> Floki.text() |> squish()))
  end

  defp notes(variable) do
    variable
    |> Floki.find(".media-source-note")
    |> Enum.map(&(&1 |> Floki.text() |> squish()))
  end

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  @media ~w(portrait brochure clip album empty_image)

  test "in a synchronized translation, the page's media variables show the note and no controls", c do
    vars = c.conn |> open(c.target.id) |> page_vars(c.target)

    for key <- @media do
      variable = Map.fetch!(vars, key)
      assert locked?(variable), "#{key} is not locked"
      # Configure opens the asset's dialog, which shows the asset and the note
      assert buttons(as_shown(variable)) -- ["Configure"] == [], "#{key} shows #{inspect(buttons(as_shown(variable)))}"
      assert Enum.any?(notes(variable), &String.ends_with?(&1, @note)), "#{key} has no note"
    end

    # A text variable is the translation's own
    tagline = Map.fetch!(vars, "tagline")
    assert [_] = Floki.find(as_shown(tagline), "input[name$='[value]']:not([disabled])")
  end

  test "in the source, the page's media variables keep their controls", c do
    vars = c.conn |> open(c.source.id) |> page_vars(c.source)

    for key <- @media do
      variable = Map.fetch!(vars, key)
      refute locked?(variable)
      assert buttons(variable) -- ["Configure"] != [], "#{key} has no controls"
    end
  end
end
