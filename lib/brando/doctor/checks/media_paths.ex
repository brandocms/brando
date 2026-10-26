defmodule Brando.Doctor.Checks.MediaPaths do
  @moduledoc """
  Image and file rows whose stored path leaves the media folder: an image's
  `path` or one of its `sizes`, or a file's `filename`, that is absolute,
  starts with `~/` or climbs out with `..` (`Brando.Tenant.Storage.safe_media_path?/1`).

  Brando refuses such paths when they are saved, and every file operation
  refuses a row that has one. A row stored before that check, or by hand,
  keeps it: the crop editor may have written an upload to the place it names.
  The check lists these rows, deleted ones included, so they can be looked at
  and cleaned up.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Doctor.Context
  alias Brando.Files.File
  alias Brando.Images.Image
  alias Brando.Tenant.Storage

  @impl true
  def id, do: "media_paths"

  @impl true
  def label, do: dgettext("doctor", "Media paths")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&escaping/0)
    |> evaluate()
  end

  @doc """
  The rows of the current prefix with a stored path that leaves the media
  folder, as `{:image | :file, id, [path]}`, by id.
  """
  @spec escaping() :: [{:image | :file, integer(), [String.t()]}]
  def escaping, do: escaping_images() ++ escaping_files()

  # The query only narrows the rows down to the paths that could leave the
  # folder; `Storage.safe_media_path?/1` decides.
  defp escaping_images do
    query =
      from i in Image,
        where:
          like(i.path, "/%") or like(i.path, "~%") or like(i.path, "%..%") or
            fragment("?::text ~ ?", i.sizes, ~S{"(/|~)|\.\.}),
        order_by: i.id,
        select: {i.id, i.path, i.sizes}

    for {id, path, sizes} <- Brando.Repo.all(query),
        paths = unsafe([path | Map.values(sizes || %{})]),
        paths != [],
        do: {:image, id, paths}
  end

  defp escaping_files do
    query =
      from f in File,
        where: like(f.filename, "/%") or like(f.filename, "~%") or like(f.filename, "%..%"),
        order_by: f.id,
        select: {f.id, f.filename}

    for {id, filename} <- Brando.Repo.all(query),
        paths = unsafe([filename]),
        paths != [],
        do: {:file, id, paths}
  end

  defp unsafe(paths), do: paths |> Enum.filter(&(is_binary(&1) and not Storage.safe_media_path?(&1))) |> Enum.uniq()

  @doc "Turns `[{environment_label, rows}]`, rows as `escaping/0` returns them, into a result."
  def evaluate(per_environment) do
    items =
      for {label, rows} <- per_environment, {kind, id, paths} <- rows do
        Context.label_item(label, "#{kind_label(kind)} #{id}: #{Enum.join(paths, ", ")}")
      end

    case length(items) do
      0 ->
        ok(dgettext("doctor", "every image and file is inside the media folder"))

      count ->
        error(
          dngettext(
            "doctor",
            "%{count} image or file stored with a path outside the media folder",
            "%{count} images or files stored with a path outside the media folder",
            count
          ),
          fix:
            dgettext(
              "doctor",
              "look for files written to these paths outside the media folder and remove them, then delete each row or have a superuser correct its path"
            ),
          link: {BrandoAdmin.Images.ImageListLive, dgettext("doctor", "Open images")},
          items: items
        )
    end
  end

  defp kind_label(:image), do: dgettext("doctor", "image")
  defp kind_label(:file), do: dgettext("doctor", "file")
end
