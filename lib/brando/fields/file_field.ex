defmodule Brando.Field.FileField do
  @moduledoc """
  Deprecated for Brando.Field.File.Schema
  """

  defmacro __using__(_) do
    raise "`use Brando.Field.FileField` is deprecated. Call `use Brando.Field.File.Schema` instead."
  end
end
