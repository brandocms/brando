defmodule Brando.Files.File do
  @moduledoc """
  Embedded file

  Also used by the files_files table (Brando.File)
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Files",
    schema: "File",
    singular: "file",
    plural: "files",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  attributes do
    attribute :path, :text, required: true
    attribute :size, :integer
    attribute :mimetype, :string
    attribute :cdn, :boolean, default: false
  end

  @derive {Jason.Encoder,
           only: [
             :id,
             :path,
             :size,
             :mimetype,
             :cdn
           ]}
end
