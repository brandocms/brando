defmodule Brando.MarkdownSources.SignatureCheck do
  @moduledoc false
  # Computes the GitHub Markdown webhook's signatures one at a time, on one
  # process, so a flood of unsigned bodies for a known connection key costs at
  # most one scheduler. A busy check makes a request wait, never refuses it: its
  # signature is unknown until it has run, so a refusal here would let unsigned
  # requests refuse signed ones. Held only for the computation, after the plug
  # has read the body.
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def init(state), do: {:ok, state}

  @doc "The result of `check`, run here. It has to be total."
  def run(check) when is_function(check, 0), do: GenServer.call(__MODULE__, {:run, check}, :infinity)

  # The closure holds a body of up to 1 MiB: hibernating collects it, where an
  # idle process would keep it referenced until its next garbage collection.
  def handle_call({:run, check}, _from, state), do: {:reply, check.(), state, :hibernate}
end
