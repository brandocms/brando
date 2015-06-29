defmodule Brando.Villain.Model do
  @moduledoc """
  Villain model tools

  ## Usage

      use Brando.Villain.Model

  Add fields to your model:

      schema "my_model" do
        field "header", :string
        villain
      end

  """

  defmacro __using__(_) do
    quote do
      import Brando.Villain.Model

      before_insert :generate_html
      before_update :generate_html

      @doc """
      Callback from before_insert/before_update to generate HTML.
      Takes the model's `json` field and transforms to `html`.
      """
      def generate_html(changeset) do
        if Ecto.Changeset.get_change(changeset, :data) do
          changeset |> Ecto.Changeset.put_change(:html, Brando.Villain.parse(changeset.changes.data))
        else
          changeset
        end
      end
    end
  end

  defmacro villain do
    quote do
      Ecto.Schema.field(:data, Brando.Type.Json)
      Ecto.Schema.field(:html, :string)
    end
  end
end