defmodule Brando.Blueprint.Villain.Blocks.HeaderBlock do
  alias Brando.Blueprint.Villain.Blocks

  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :uid, :string
    field :type, :string
    field :hidden, :boolean, default: false
    field :deleted, :boolean, default: false

    embeds_one :data, Data, primary_key: false do
      field :text, :string
      field :level, :integer
      field :class, :string
    end
  end
end
