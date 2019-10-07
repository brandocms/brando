defmodule Brando.Sequence.Channel do
  @moduledoc """
  Sequencing logic for channels.

  ## Usage

      use Brando.Sequence.Channel
      sequence "projects", Projects.Project

  """

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  defmacro sequence(key, module) do
    quote generated: true do
      @doc false
      def handle_in("#{unquote(key)}:sequence_#{unquote(key)}", %{"ids" => ids}, socket) do
        unquote(module).sequence(ids, Range.new(0, length(ids)))
        {:reply, {:ok, %{code: 200}}, socket}
      end
    end
  end
end
