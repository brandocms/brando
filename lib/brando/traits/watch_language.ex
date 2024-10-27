defmodule Brando.Trait.WatchLanguage do
  @moduledoc """
  Watch language changes
  """
  use Brando.Trait

  @doc """
  Watch for language change
  """
  def after_save(entry, _changeset, :system), do: entry

  def after_save(entry, %{changes: %{language: _new_lang}}, _user) do
    # TODO: update navigation for new language
    entry
  end

  def after_save(entry, _changeset, _user), do: entry
end
