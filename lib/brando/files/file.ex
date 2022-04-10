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

  identifier "{{ entry.id }}"

  attributes do
    attribute :title, :text
    attribute :mime_type, :string, required: true
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

        <small class="monospace">{{ entry.filename }}</small><br>
        <small class="monospace">{{ entry.config_target }}</small>
        """,
        columns: 8
      )

      template(
        """
        <small class="monospace">{{ entry.filesize | filesize }}</small>
        """,
        columns: 2
      )

      actions([
        [label: t("Duplicate file"), event: "duplicate_entry"],
        [
          label: t("Delete file"),
          event: "delete_entry",
          confirm: t("Are you sure?")
        ]
      ])

      selection_actions([
        [label: t("Delete files"), event: "delete_selected"]
      ])
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

  defimpl Phoenix.HTML.Safe, for: __MODULE__ do
    def to_iodata(file) do
      file
      |> Brando.Utils.file_url()
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end

  defimpl String.Chars, for: __MODULE__ do
    def to_string(file) do
      file
      |> Brando.Utils.file_url()
    end
  end
end
