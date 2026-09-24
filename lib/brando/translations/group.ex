defmodule Brando.Translations.Group do
  @moduledoc """
  The language versions of one synchronized entry.

  `source_generation` counts source saves; pending versions and members record
  the generation they were computed from.
  """
  use Ecto.Schema

  alias Brando.Translations.Member

  schema "translation_groups" do
    field :entry_type, :string
    field :source_generation, :integer, default: 0
    has_many :members, Member
    timestamps()
  end
end
