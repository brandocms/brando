defmodule Brando.Villain.Migration do
  @moduledoc """
  Interface to Villain HTML editor.
  https://github.com/twined/villain

    # Migration

  Migration utilities

  ## Usage

      use Brando.Villain, :migration

  Add fields to your schema:

      table "bla" do
        villain()
      end

  """
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc """
  Macro for villain migrations.
  """
  defmacro villain(field \\ nil) do
    data_field = (field && field |> to_string |> Kernel.<>("_data") |> String.to_atom()) || :data

    html_field = (field && field |> to_string |> Kernel.<>("_html") |> String.to_atom()) || :html

    quote do
      Ecto.Migration.add(unquote(data_field), :jsonb)
      Ecto.Migration.add(unquote(html_field), :text)
    end
  end

  @doc """
  Takes the schema's `json` field and transforms to `html`.

  This is usually called from your schema's `changeset` functions:

      def changeset(schema, :create, params) do
        schema
        |> cast(params, @required_fields, @optional_fields)
        |> generate_html()
      end
  """
  def generate_html(
        changeset,
        field \\ nil,
        parser_mod \\ Brando.config(Brando.Villain)[:parser]
      ) do
    data_field = (field && field |> to_string |> Kernel.<>("_data") |> String.to_atom()) || :data
    html_field = (field && field |> to_string |> Kernel.<>("_html") |> String.to_atom()) || :html

    if Ecto.Changeset.get_change(changeset, data_field) do
      parsed_data = Brando.Villain.parse(Map.get(changeset.changes, data_field), parser_mod)
      Ecto.Changeset.put_change(changeset, html_field, parsed_data)
    else
      changeset
    end
  end
end
