defmodule Brando.Content.TableRow do
  @moduledoc """
  Blueprint for table rows

  Table rows are used in blocks for a flexible table structure.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "TableRow",
    singular: "table_row",
    plural: "table_rows",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped

  identifier false
  persist_identifier false

  relations do
    relation :block, :belongs_to, module: Brando.Content.Block

    relation :vars, :has_many,
      module: Brando.Content.Var,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      cast: true
  end

  translations do
    context :naming do
      translate :singular, t("table row")
      translate :plural, t("table rows")
    end
  end
end
