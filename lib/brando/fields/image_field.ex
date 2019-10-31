defmodule Brando.Field.ImageField do
  @moduledoc """
  Deprecated for Brando.Field.Image.Schema
  """

  defmacro __using__(_) do
    raise "`use Brando.Field.ImageField` is deprecated. Call `use Brando.Field.Image.Schema` instead."
  end
end
