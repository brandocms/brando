defmodule Brando.MarkdownSources.ReadSlots do
  @moduledoc false
  # Bounds how many bodies from GitHub's addresses the GitHub Markdown webhook
  # holds at once: such a request reads, verifies and accepts its body holding
  # one of 16 slots, so they take at most 16 MiB however many arrive together,
  # and however long the database takes to store a delivery. Their budget
  # per minute is larger than other clients' (`Brando.MarkdownSources.RateLimiter`),
  # so it bounds their reads a minute, not those at once. A request waits for a
  # slot, first come first served, and is refused only when its deadline passes:
  # a refusal at once would let wrongly signed requests refuse correctly signed
  # ones. A slot whose holder dies is given back (`Brando.MarkdownSources.Slots`).
  alias Brando.MarkdownSources.Slots

  @slots 16

  def child_spec(_), do: Slots.child_spec(name: __MODULE__, slots: @slots)

  @doc """
  The result of `fun`, run holding a slot; `{:error, :busy}` when no slot is free
  before `deadline` (monotonic milliseconds).
  """
  def run(deadline, fun), do: Slots.run(__MODULE__, deadline, fun)
end
