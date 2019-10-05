defmodule Brando.Sequence.View do
  @moduledoc """
  Sequence rendering for view

  ## Usage

      use Brando.Sequence.View

  """
  defmacro __using__(_) do
    quote do
      def render("sequence_post.json", _assigns), do: %{status: "200"}
    end
  end
end
