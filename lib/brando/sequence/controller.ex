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
        Brando.Traits.Sequence.sequence(unquote(schema_module), %{"ids" => ids})
        render(conn, :sequence_post)
      end
    end
  end
end
