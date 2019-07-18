defmodule Brando.Villain.Migration do
  @moduledoc """
  Interface to Villain HTML editor.
  https://github.com/twined/villain

    # Migration

  Migration utilities

  ## Usage

      use Brando.Villain.Migration

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
end
