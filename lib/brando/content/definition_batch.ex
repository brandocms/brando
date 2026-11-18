defmodule Brando.Content.DefinitionBatch do
  @moduledoc """
  One apply of a release's module definitions in this environment, or one
  revert of such an apply, in `content_definition_batches`. The rows of
  `Brando.Content.DefinitionApply` it wrote share its `batch_id`.

    * `source` - `:release`, or `:revert` for a revert
    * `release` - the release version
    * `run_id` - the entry renders it queued (`Brando.Content.Definitions.track_refresh/1`)
    * `definitions` - `%{"items" => [%{"uid", "kind", "action", "name"}]}`,
      what it changed, for the admin
    * `reverts_batch_id` - for a revert, the apply it reverted
    * `confirmed_at`, `confirmed_by`, `confirmed_how` - when an apply was
      kept: `:kept` by a superuser, or `:next_apply`, confirmed by the next
      release apply. Until then it can be reverted
    * `reverted_at`, `reverted_by`, `revert_batch_id` - when it was reverted,
      and the revert's own batch

  See the [module definitions guide](module_definitions.md).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "content_definition_batches" do
    field :batch_id, Ecto.UUID
    field :source, Ecto.Enum, values: [:release, :revert]
    field :release, :string
    field :run_id, :string
    field :definitions, :map, default: %{}
    field :reverts_batch_id, Ecto.UUID
    belongs_to :applied_by, Brando.Users.User
    field :applied_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    belongs_to :confirmed_by, Brando.Users.User
    field :confirmed_how, Ecto.Enum, values: [:kept, :next_apply]
    field :reverted_at, :utc_datetime_usec
    belongs_to :reverted_by, Brando.Users.User
    field :revert_batch_id, Ecto.UUID
  end
end
