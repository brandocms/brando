# credo:disable-for-this-file
defmodule Brando.Sequence do
  @moduledoc """
  Helpers for sequencing schema data.
  """
  defmacro __using__(:view) do
    raise "`use Brando.Sequence, :view` is deprecated. Call `use Brando.Sequence.View` instead."
  end

  defmacro __using__(:controller) do
    raise "`use Brando.Sequence, :controller` is deprecated. Call `use Brando.Sequence.Controller` instead."
  end

  defmacro __using__(:channel) do
    raise "`use Brando.Sequence, :channel` is deprecated. Call `use Brando.Sequence.Channel` instead."
  end

  defmacro __using__(:schema) do
    raise "`use Brando.Sequence, :schema` is deprecated. Call `use Brando.Sequence.Schema` instead."
  end

  defmacro __using__(:migration) do
    raise "`use Brando.Sequence, :migration` is deprecated. Call `use Brando.Sequence.Migration` instead."
  end
end
