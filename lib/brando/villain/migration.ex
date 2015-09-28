defmodule Brando.Villain.Migration do
  @moduledoc """
  Villain migration tools

  ## Usage

      use Brando.Villain.Migration

  Add fields to your model:

      table "bla" do
        villain
      end

  """

  defmacro __using__(_) do
    quote do
      import Brando.Villain.Migration
    end
  end

  defmacro villain do
    quote do
      Ecto.Migration.add(:data, :json)
      Ecto.Migration.add(:html, :text)
    end
  end
end
