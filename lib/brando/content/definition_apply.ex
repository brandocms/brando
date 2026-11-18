defmodule Brando.Content.DefinitionApply do
  @moduledoc """
  One definition applied from files in this environment, or found equal to
  them and recorded as applied: a row per module or table template per apply,
  in `content_definition_applies`.

  The latest row for a definition (`kind` and `uid`) is the environment's own
  baseline. Planning a release's definitions compares the database with that
  row's `digest`, not with the lockfile, which describes the database the
  files were last imported into in development. The rows are kept, so they
  also tell who applied what and when, and from which release.

    * `kind` - `"module"` or `"table_template"`
    * `digest` - the definition as applied, as a lockfile baseline (version 2)
      records it
    * `previous_digest`, `previous` - the definition the apply replaced, in
      the same canonical form, or nil for a create or an adoption
    * `action` - `:created`, `:updated`, `:replaced` (applied over a database
      copy that was never applied from files, or edited here since the last
      apply, because the operator chose the files' version), `:adopted` (the
      database already equalled the files), `:kept` (a superuser chose to keep
      the version edited here over the release's: the release's file is
      recorded as applied, so it waits no longer, and the admin's edit stays)
      or `:reverted` (an apply was reverted: `digest` is the definition it
      restored)
    * `source` - `:release` (the release's own definitions), `:import` (the
      CLI, the admin's ZIP import or the dev watcher) or `:revert`
    * `release` - the release version, for `:release`
    * `references` - the media and content tokens the definition uses, bound
      to this environment's records, so the next release reuses them
    * `batch_id` - shared by the rows of one apply (`Brando.Content.DefinitionBatch`
      for a release apply or a revert)
    * `applied_by` - the account, or nil for the system

  See the [module definitions guide](module_definitions.md).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @actions [:created, :updated, :replaced, :adopted, :kept, :reverted]
  @sources [:release, :import, :revert]

  schema "content_definition_applies" do
    field :kind, :string
    field :uid, :string
    field :digest, :string
    field :previous_digest, :string
    field :previous, :map
    field :action, Ecto.Enum, values: @actions
    field :source, Ecto.Enum, values: @sources
    field :release, :string
    field :references, :map, default: %{}
    field :batch_id, Ecto.UUID
    belongs_to :applied_by, Brando.Users.User
    field :applied_at, :utc_datetime_usec
  end
end
