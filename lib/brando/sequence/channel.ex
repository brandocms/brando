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
      def handle_in("#{unquote(key)}:sequence_#{unquote(key)}", params, socket) do
        Brando.Trait.Sequenced.sequence(unquote(module), params)
        {:reply, {:ok, %{code: 200}}, socket}
      end
    end
  end
end
