defmodule Brando.Sequence.Controller do
  @moduledoc """
  Sequencing logic for controller.
  """

  defmacro __using__(schema: schema_module) do
    quote do
      @doc """
      Sequence schema and render :sequence post
      """
      def sequence_post(conn, %{"order" => ids}) do
        unquote(schema_module).sequence(ids, Range.new(0, length(ids)))
        render(conn, :sequence_post)
      end
    end
  end
end
