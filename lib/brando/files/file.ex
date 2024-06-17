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

  import Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped

  identifier false

  attributes do
    attribute :title, :text
    attribute :mime_type, :string, default: "application/octet-stream", required: true
    attribute :filesize, :integer, required: true
    attribute :filename, :text, required: true
    attribute :config_target, :text, required: true
    attribute :cdn, :boolean, default: false
  end

  listings do
    listing do
      listing_query %{
        order: [{:desc, :id}]
      }

      filters([
        [label: t("Filename"), filter: "filename"]
      ])

      template(
        """
        <small class="monospace">\#{{ entry.id }}</small>
        """,
        columns: 1
      )

      template(
        """

        <small class="monospace"><strong>{{ entry.filename }}</strong></small><br>
        <small class="monospace tiny">{{ entry | media_url }}</small>
        """,
        columns: 7
      )

      template(
        """
        <small class="monospace">{{ entry.filesize | filesize }}</small>
        """,
        columns: 2
      )

      template(
        """
        <a href="{{ entry | media_url }}" target="_blank">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M18.364 15.536L16.95 14.12l1.414-1.414a5 5 0 1 0-7.071-7.071L9.879 7.05 8.464 5.636 9.88 4.222a7 7 0 0 1 9.9 9.9l-1.415 1.414zm-2.828 2.828l-1.415 1.414a7 7 0 0 1-9.9-9.9l1.415-1.414L7.05 9.88l-1.414 1.414a5 5 0 1 0 7.071 7.071l1.414-1.414 1.415 1.414zm-.708-10.607l1.415 1.415-7.071 7.07-1.415-1.414 7.071-7.07z"/></svg>
        </a>
        """,
        columns: 1
      )
    end
  end

  @derive {Jason.Encoder,
           only: [
             :title,
             :mime_type,
             :filesize,
             :filename,
             :config_target,
             :cdn
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
      file
      |> Brando.Utils.file_url()
    end
  end
end
