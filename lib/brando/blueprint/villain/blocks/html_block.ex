defmodule Brando.Blueprint.Villain.Blocks.HtmlBlock do
  defmodule Data do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :text, :string
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w(text)a)
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "html"
end
