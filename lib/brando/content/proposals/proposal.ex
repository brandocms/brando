defmodule Brando.Content.Proposals.Proposal do
  @moduledoc """
  An immutable, validated set of content operations.

    * `targets` — the saved baseline of each existing entry, keyed by
      `{schema, id}`, and the schema of each new entry, keyed by `{:new, ref}`
    * `fingerprints` — the baseline fingerprint of each existing entry;
      a preview or apply against changed content is refused
    * `module_versions` — the version of every module a block is built from
    * `problems` — blocking validation problems; an empty list means the
      proposal can be applied
    * `effects` — counts for review, and the published entries the proposal
      changes live
  """
  defstruct [
    :id,
    :scope,
    :actor_id,
    version: 1,
    operations: [],
    targets: %{},
    fingerprints: %{},
    module_versions: %{},
    problems: [],
    effects: %{}
  ]

  @type target :: {module(), integer()} | {:new, String.t()}
  @type t :: %__MODULE__{}

  @doc "A stable string key for a target, used in receipts and preview maps."
  @spec key(target) :: String.t()
  def key({:new, ref}), do: "new:#{ref}"
  def key({schema, id}), do: "#{inspect(schema)}:#{id}"
end
