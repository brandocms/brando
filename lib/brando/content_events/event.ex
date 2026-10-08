defmodule Brando.ContentEvents.Event do
  @moduledoc """
  One content event, as subscribers receive it (see `Brando.ContentEvents`).

    * `id` — a UUID, the same for every subscriber and every redelivery of
      this event. Use it to ignore an event you have already handled.
    * `type` — `"entry.created"`, `"entry.updated"`, `"entry.published"`,
      `"entry.unpublished"`, `"entry.deleted"` or `"entry.restored"`.
    * `occurred_at` — when the change was saved (the last save, for a
      debounced `entry.updated`).
    * `site` and `environment` — the keys of the site and environment it
      happened in. `environment` is `nil` without tenancy.
    * `schema` — the blueprint module, and `entry_type` its public name,
      `"<domain>.<schema>"` in lowercase, such as `"projects.project"`.
    * `entry_id`, `language`, `status` (`"published"`, `"draft"`…) and
      `url`, the entry's absolute URL when its blueprint gives it one.
    * `changed_fields` — the names of the fields the change saved. Never
      their values.
    * `actor` — what made the change: `"person"`, `"assistant"`, `"mcp"`,
      `"scheduler"` or `"system"`. Who the person was is not part of the
      event.
  """

  @enforce_keys [:id, :type, :occurred_at]
  defstruct [
    :id,
    :type,
    :occurred_at,
    :site,
    :environment,
    :schema,
    :entry_type,
    :entry_id,
    :language,
    :status,
    :url,
    changed_fields: [],
    actor: "system"
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          occurred_at: DateTime.t(),
          site: String.t() | nil,
          environment: String.t() | nil,
          schema: module() | nil,
          entry_type: String.t() | nil,
          entry_id: integer() | nil,
          language: String.t() | nil,
          status: String.t() | nil,
          url: String.t() | nil,
          changed_fields: [String.t()],
          actor: String.t()
        }

  @doc "The public name of a blueprint's entries: `\"<domain>.<schema>\"`, lowercased."
  @spec entry_type(module() | nil) :: String.t() | nil
  def entry_type(nil), do: nil

  def entry_type(schema) when is_atom(schema) do
    %{domain: domain, schema: name} = schema.__naming__()
    String.downcase("#{domain}.#{name}")
  rescue
    _ -> nil
  end
end
