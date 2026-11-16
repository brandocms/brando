defmodule Brando.Users.DefaultContentLanguage do
  @moduledoc false
  # Gives a user's new `config` the installation's `config :brando,
  # :default_language` as its content language when it has none. Read when the
  # user is saved, not when Brando compiles, so it follows `config/runtime.exs`
  # and a changed configuration without recompiling Brando.
  #
  # When the changeset is written (`prepare_changes/2`), so a `config` put after
  # the Blueprint changeset (`Changeset.put_embed/3`) gets it too. A user read
  # for a session whose config has none gets it there (`fill/1`).
  use Brando.Trait

  alias Ecto.Changeset

  @impl true
  def changeset_mutator(_module, _config, changeset, _user, _opts),
    do: Changeset.prepare_changes(changeset, &put_default/1)

  defp put_default(%Changeset{changes: %{config: %Changeset{action: :insert} = config}} = changeset) do
    if is_nil(Changeset.get_field(config, :content_language)) do
      config = Changeset.put_change(config, :content_language, Brando.Languages.installation_default_language())
      %{changeset | changes: Map.put(changeset.changes, :config, config)}
    else
      changeset
    end
  end

  defp put_default(changeset), do: changeset

  @doc """
  `user` with the installation's default content language in its `config` when
  the config has none: one saved without it, or built as `%UserConfig{}`.
  """
  @spec fill(map()) :: map()
  def fill(%{config: %{content_language: nil} = config} = user),
    do: %{user | config: %{config | content_language: Brando.Languages.installation_default_language()}}

  def fill(user), do: user
end
