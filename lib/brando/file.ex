# defmodule Brando.File do
#   @moduledoc """
#   Ecto schema for the File schema

#   #TODO Figure out if we actually will use this as a file db
#   """

#   use Brando.Blueprint,
#     application: "Brando",
#     domain: "Files",
#     schema: "File",
#     singular: "file",
#     plural: "files",
#     gettext_module: Brando.Gettext

#   trait Brando.Trait.Creator
#   trait Brando.Trait.Sequenced
#   trait Brando.Trait.SoftDelete
#   trait Brando.Trait.Timestamped

#   identifier "{{ entry.id }}"

#   assets do
#     asset :file, :file, cfg: :db
#   end

#   @derive {Jason.Encoder,
#            only: [
#              :id,
#              :file
#            ]}
# end
