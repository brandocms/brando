defmodule Brando.Content.BlockIdentifier do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "BlockIdentifier",
    singular: "block_identifier",
    plural: "block_identifiers",
    gettext_module: Brando.Gettext

  @allow_mark_as_deleted true
  trait Brando.Trait.Sequenced

  relations do
    relation :block, :belongs_to, module: Brando.Content.Block
    relation :identifier, :belongs_to, module: Brando.Content.Identifier
  end
end
