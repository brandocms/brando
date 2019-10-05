defmodule Brando.Sequence.Migration do
  @moduledoc """
  Sequencing macro for migrations.

  ## Usage

      use Brando.Sequence.Migration

      alter table(:example) do
        sequenced()
      end

  """
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  defmacro sequenced do
    quote do
      Ecto.Migration.add(:sequence, :integer, default: 0)
    end
  end
end
