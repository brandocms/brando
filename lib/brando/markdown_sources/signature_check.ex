defmodule Brando.MarkdownSources.SignatureCheck do
  @moduledoc false
  # Computes the GitHub Markdown webhook's signatures one at a time, so a flood
  # of wrongly signed bodies for a known connection key costs at most one
  # scheduler. A request computes its own, in its own process, holding the one
  # turn (`Brando.MarkdownSources.Slots`), so its body is never copied here or
  # left behind when it gives up. A busy check makes a request wait, rather than
  # refusing it: a signature is unverified until it has run, so a refusal at once
  # would let wrongly signed requests refuse correctly signed ones. It waits
  # until its deadline and is then refused, giving back its read slot
  # (`Brando.MarkdownSources.ReadSlots`). A request from GitHub's addresses goes
  # ahead of the others: at most 16 of those wait at once, so a flood for the key
  # from other addresses delays a genuine delivery by the check that is running,
  # not by the whole line.
  alias Brando.MarkdownSources.Slots

  def child_spec(_), do: Slots.child_spec(name: __MODULE__, slots: 1)

  @doc """
  The result of `check`, run holding the turn; `{:error, :busy}` when the turn
  does not come before `deadline` (monotonic milliseconds). `github?` puts the
  request ahead of those from other addresses.
  """
  def run(check, opts \\ []) when is_function(check, 0) do
    line = if Keyword.get(opts, :github?, false), do: :first, else: :others
    Slots.run(__MODULE__, Keyword.get(opts, :deadline, :infinity), check, line)
  end
end
