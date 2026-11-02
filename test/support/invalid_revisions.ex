defmodule Brando.InvalidRevisions do
  @moduledoc """
  A page revision that no longer validates in a nested record: its var has
  lost its required label, as when a field becomes required after the
  revision was taken. The page's own fields still validate, so restoring it
  gives a changeset with errors under `vars` only, none at the top level.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Revisions.Revision

  @doc "A page and the number of its revision with an invalid var; the page has changed since."
  def page_with_invalid_var!(user) do
    var = %{type: :text, label: "Label", key: "key-#{System.unique_integer([:positive])}", value: "Value"}
    {:ok, page} = Pages.create_page(Factory.params_for(:page, vars: [var]), user)

    query =
      from r in Revision,
        where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id,
        order_by: [desc: r.revision],
        limit: 1

    %{revision: revision, encoded_entry: encoded} = Repo.one!(query)
    entry = :erlang.binary_to_term(encoded)
    invalid = %{entry | vars: Enum.map(entry.vars, &%{&1 | label: nil})}

    {1, _} =
      Repo.update_all(
        from(r in Revision,
          where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id and r.revision == ^revision
        ),
        set: [encoded_entry: Brando.Utils.term_to_binary(invalid)]
      )

    {:ok, page} = Pages.update_page(page.id, %{title: "Changed since"}, user)
    {page, revision}
  end

  @doc "A job struct for the scheduled restore of `revision` of `entry`, built without a row."
  def scheduled_job(%schema{id: id}, revision, user) do
    %Oban.Job{
      attempt: 1,
      max_attempts: 10,
      args: %{"schema" => to_string(schema), "id" => id, "revision" => revision, "user_id" => user.id}
    }
  end
end
