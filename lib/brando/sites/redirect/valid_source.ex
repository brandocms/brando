defmodule Brando.Sites.Redirect.ValidSource do
  @moduledoc """
  Checks that a redirect's `from` compiles as a pattern. Every 404 in the
  redirect's language is matched against it.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    Ecto.Changeset.validate_change(changeset, :from, fn :from, from ->
      case Brando.Sites.Redirects.compile(from) do
        {:ok, _regex} -> []
        :error -> [from: gettext("is not a valid pattern")]
      end
    end)
  end
end
