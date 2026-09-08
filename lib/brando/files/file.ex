defmodule Brando.Files.File do
  @moduledoc """
  Ecto schema for the File schema
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Files",
    schema: "File",
    singular: "file",
    plural: "files",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext
  import Brando.Blueprint.Listings.Components.Core

  trait :creator
  trait :soft_delete
  trait :timestamped

  identifier false
  persist_identifier false

  attributes do
    attribute :title, :text
    attribute :mime_type, :string, default: "application/octet-stream", required: true
    attribute :filesize, :integer, required: true
    attribute :filename, :text, required: true
    attribute :config_target, :text, required: true
    attribute :cdn, :boolean, default: false
    attribute :folder_id, :integer
  end

  listings do
    listing do
      query %{order: [{:desc, :id}]}
      filter label: t("Filename"), key: "filename"
      action label: t("Replace file"), event: "replace_file"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.field columns={1} class="library-thumbnail library-file-icon">
      <Brando.HTML.Icon.icon name="hero-document" />
    </.field>
    <.field columns={7} class="library-image-info">
      <a class="entry-link" href={Brando.Utils.media_url(@entry)} target="_blank" rel="noopener">{URI.decode(@entry.filename)}</a>
      <div :if={@entry.title && @entry.title != @entry.filename} class="library-image-title">{@entry.title}</div>
      <div class="library-image-meta">
        <span class="library-format">{String.upcase(String.trim_leading(Path.extname(@entry.filename), "."))}</span>
        <span>{Brando.Utils.human_size(@entry.filesize)}</span>
        <span :if={@entry.mime_type}>{@entry.mime_type}</span>
      </div>
    </.field>
    <.field columns={1} class="library-file-action">
      <a
        href={Brando.Utils.media_url(@entry)}
        target="_blank"
        rel="noopener"
        class="workspace-button"
        aria-label={gettext("Open %{filename}", filename: @entry.filename)}
      >{gettext("Open file")}</a>
    </.field>
    """
  end

  translations do
    context :naming do
      translate :singular, t("file")
      translate :plural, t("files")
    end
  end

  @derive {Jason.Encoder,
           only: [
             :title,
             :mime_type,
             :filesize,
             :filename,
             :config_target,
             :cdn,
             :folder_id
           ]}

  defimpl Phoenix.HTML.Safe do
    def to_iodata(file) do
      file
      |> Brando.Utils.file_url()
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end

  defimpl String.Chars do
    def to_string(file) do
      Brando.Utils.file_url(file)
    end
  end
end
