defmodule BrandoAdmin.Components.Assets.SortByUse do
  @moduledoc """
  The media libraries' "Sort by use" and "Delete unused", shared by images,
  videos and files: the header buttons, the preview of where a folder's
  assets would go (`BrandoAdmin.Media.Sweep`), the bar offering Undo after the
  move, and the toasts. Each takes the library's `asset_type`.

  The LiveViews own the events: `sweep_open`, `sweep_close`, `sweep_apply`,
  `sweep_undo`, `sweep_dismiss` and `delete_unused` (see
  `BrandoAdmin.LiveView.AssetListHelpers`).
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias Phoenix.LiveView.JS

  attr :asset_type, :atom, required: true

  @doc "Opens the preview for the current folder."
  def sort_button(assigns) do
    ~H"""
    <button
      type="button"
      class="folder-action"
      phx-click="sweep_open"
      data-testid="sweep-open"
      data-tooltip={sort_description(@asset_type)}
    >
      <.icon name="folder-down" />{gettext("Sort by use")}
    </button>
    """
  end

  attr :asset_type, :atom, required: true
  attr :count, :integer, required: true

  @doc "With the Not in use filter on: deletes every unused asset in view, after a confirmation."
  def delete_unused_button(assigns) do
    ~H"""
    <button
      type="button"
      class="folder-action is-destructive"
      phx-click="delete_unused"
      data-testid="delete-unused"
      data-confirm-destructive
      data-confirm={delete_question(@asset_type, @count)}
    >
      <.icon name="trash" />{ngettext(
        "Delete %{count} unused",
        "Delete all %{count} unused",
        @count,
        count: @count
      )}
    </button>
    """
  end

  attr :asset_type, :atom, required: true
  attr :result, :map, required: true

  @doc "What the sort did, with the way back, above the listing."
  def result(assigns) do
    ~H"""
    <div class="media-sweep-result" role="status" data-testid="sweep-result">
      <.icon name="circle-check" />
      <span>
        {gettext("Sorted %{assets} into %{folders}.",
          assets: count_label(@asset_type, @result.moved),
          folders: ngettext("%{count} folder", "%{count} folders", @result.folders, count: @result.folders)
        )}
      </span>
      <button type="button" class="media-sweep-undo" phx-click="sweep_undo">{gettext("Undo")}</button>
      <button
        type="button"
        class="media-sweep-dismiss"
        phx-click="sweep_dismiss"
        aria-label={gettext("Dismiss")}
        data-tooltip={gettext("Dismiss")}
      >
        <.icon name="x" />
      </button>
    </div>
    """
  end

  attr :sweep, :map, required: true, doc: "`%{plan: plan, samples: %{id => asset}}`"

  @doc "The preview: a row per entry, to leave out or rename, and the move."
  def modal(assigns) do
    plan = assigns.sweep.plan
    sorted = plan.groups |> Enum.map(&length(&1.ids)) |> Enum.sum()

    assigns =
      assigns
      |> assign(:plan, plan)
      |> assign(:asset_type, plan.asset_type)
      |> assign(:sorted, sorted)

    ~H"""
    <Content.modal
      id={"#{@asset_type}-sweep"}
      title={gettext("Sort by use")}
      subtitle={String.replace(@plan.folder, "/", " › ")}
      icon="folder-down"
      show
      wide
      close={JS.push("sweep_close")}
    >
      <form id={"#{@asset_type}-sweep-form"} class="media-sweep" phx-submit="sweep_apply">
        <p class="media-sweep-lede">
          {lede(@asset_type, @sorted)}
          <span :if={@plan.groups != [] and @plan.unused > 0}>{unused_note(@asset_type, @plan.unused)}</span>
        </p>

        <ul :if={@plan.groups != []} class="media-sweep-groups">
          <li :for={group <- @plan.groups} class="media-sweep-group">
            <label class="media-sweep-include">
              <input type="hidden" name={"include[#{group.key}]"} value="false" />
              <input type="checkbox" name={"include[#{group.key}]"} value="true" checked />
              <span class="sr-only">{gettext("Move these")}</span>
            </label>
            <div class={["media-sweep-thumbs", "media-sweep-thumbs--#{@asset_type}"]}>
              <.sample
                :for={id <- Enum.take(group.ids, 4)}
                :if={@sweep.samples[id]}
                asset_type={@asset_type}
                asset={@sweep.samples[id]}
              />
            </div>
            <div class="media-sweep-entry">
              <strong>{group.label}</strong>
              <span>
                {group.type} · {count_label(@asset_type, length(group.ids))}
                <span :if={group.shared > 0}>
                  · {ngettext(
                    "%{count} also used elsewhere",
                    "%{count} also used elsewhere",
                    group.shared,
                    count: group.shared
                  )}
                </span>
              </span>
            </div>
            <input
              type="text"
              class="media-sweep-name"
              name={"name[#{group.key}]"}
              value={group.key}
              aria-label={gettext("Folder for %{entry}", entry: group.label)}
              autocomplete="off"
              spellcheck="false"
            />
          </li>
        </ul>
      </form>
      <:footer>
        <button type="button" class="secondary" phx-click="sweep_close">{gettext("Cancel")}</button>
        <button :if={@plan.groups != []} type="submit" form={"#{@asset_type}-sweep-form"} class="primary">
          {submit_label(@asset_type)}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :asset_type, :atom, required: true
  attr :asset, :any, required: true

  # An image as it is; a video by its thumbnail, else a film tile; a file as
  # a tile with its type's icon and extension.
  defp sample(%{asset_type: :image} = assigns) do
    ~H"""
    <Content.image image={@asset} size={:smallest} />
    """
  end

  defp sample(%{asset_type: :video, asset: %{thumbnail: %Brando.Images.Image{}}} = assigns) do
    ~H"""
    <Content.image image={@asset.thumbnail} size={:smallest} />
    """
  end

  defp sample(%{asset_type: :video} = assigns) do
    ~H"""
    <span class="media-sweep-tile" title={Brando.Videos.display_title(@asset)}><.icon name="film" /></span>
    """
  end

  defp sample(%{asset_type: :file} = assigns) do
    ~H"""
    <span class="media-sweep-tile" title={URI.decode(@asset.filename)}>
      <.icon name={file_icon(@asset)} />
      <span class="media-sweep-extension">{extension(@asset.filename)}</span>
    </span>
    """
  end

  @doc "The Lucide icon for a file's type, from its MIME type or extension."
  @spec file_icon(map()) :: String.t()
  def file_icon(%{mime_type: mime, filename: filename}) do
    ext = filename |> to_string() |> Path.extname() |> String.downcase()

    cond do
      String.starts_with?(to_string(mime), "image/") -> "file-image"
      String.starts_with?(to_string(mime), "video/") -> "file-play"
      String.starts_with?(to_string(mime), "audio/") -> "file-music"
      ext in ~w(.xls .xlsx .ods .csv .numbers) -> "file-spreadsheet"
      ext in ~w(.zip .rar .7z .gz .tar .tgz) -> "file-archive"
      ext in ~w(.pdf .doc .docx .odt .rtf .txt .md .pages) -> "file-text"
      true -> "file"
    end
  end

  defp extension(filename) do
    filename |> to_string() |> Path.extname() |> String.trim_leading(".") |> String.upcase()
  end

  @doc "The toast after Undo: how many assets went back."
  @spec moved_back(atom(), non_neg_integer()) :: String.t()
  def moved_back(:image, count), do: ngettext("Moved %{count} image back", "Moved %{count} images back", count)
  def moved_back(:video, count), do: ngettext("Moved %{count} video back", "Moved %{count} videos back", count)
  def moved_back(:file, count), do: ngettext("Moved %{count} file back", "Moved %{count} files back", count)

  @doc "The toast after Delete unused."
  @spec deleted(atom(), non_neg_integer()) :: String.t()
  def deleted(:image, count), do: ngettext("Deleted %{count} image", "Deleted %{count} images", count)
  def deleted(:video, count), do: ngettext("Deleted %{count} video", "Deleted %{count} videos", count)
  def deleted(:file, count), do: ngettext("Deleted %{count} file", "Deleted %{count} files", count)

  defp count_label(:image, count), do: ngettext("%{count} image", "%{count} images", count)
  defp count_label(:video, count), do: ngettext("%{count} video", "%{count} videos", count)
  defp count_label(:file, count), do: ngettext("%{count} file", "%{count} files", count)

  defp sort_description(:image), do: gettext("Sort this folder's images into folders for the entries that use them")
  defp sort_description(:video), do: gettext("Sort this folder's videos into folders for the entries that use them")
  defp sort_description(:file), do: gettext("Sort this folder's files into folders for the entries that use them")

  defp delete_question(:image, count),
    do: ngettext("Delete %{count} unused image?", "Delete all %{count} unused images?", count)

  defp delete_question(:video, count),
    do: ngettext("Delete %{count} unused video?", "Delete all %{count} unused videos?", count)

  defp delete_question(:file, count),
    do: ngettext("Delete %{count} unused file?", "Delete all %{count} unused files?", count)

  defp submit_label(:image), do: gettext("Move the images")
  defp submit_label(:video), do: gettext("Move the videos")
  defp submit_label(:file), do: gettext("Move the files")

  defp lede(:image, 0),
    do: gettext("None of the images in this folder are used by an entry, so there is nothing to sort.")

  defp lede(:video, 0),
    do: gettext("None of the videos in this folder are used by an entry, so there is nothing to sort.")

  defp lede(:file, 0), do: gettext("None of the files in this folder are used by an entry, so there is nothing to sort.")

  defp lede(:image, count) do
    ngettext(
      "%{count} image in this folder is used by an entry. It moves to a folder named after that entry; the file itself stays where it is, so no address changes.",
      "%{count} images in this folder are used by entries. Each moves to a folder named after its entry; the files themselves stay where they are, so no address changes.",
      count
    )
  end

  defp lede(:video, count) do
    ngettext(
      "%{count} video in this folder is used by an entry. It moves to a folder named after that entry; the video itself stays where it is, so no address changes.",
      "%{count} videos in this folder are used by entries. Each moves to a folder named after its entry; the videos themselves stay where they are, so no address changes.",
      count
    )
  end

  defp lede(:file, count) do
    ngettext(
      "%{count} file in this folder is used by an entry. It moves to a folder named after that entry; the file itself stays where it is, so no address changes.",
      "%{count} files in this folder are used by entries. Each moves to a folder named after its entry; the files themselves stay where they are, so no address changes.",
      count
    )
  end

  defp unused_note(:image, count),
    do: ngettext("%{count} unused image stays here.", "%{count} unused images stay here.", count)

  defp unused_note(:video, count),
    do: ngettext("%{count} unused video stays here.", "%{count} unused videos stay here.", count)

  defp unused_note(:file, count),
    do: ngettext("%{count} unused file stays here.", "%{count} unused files stay here.", count)
end
