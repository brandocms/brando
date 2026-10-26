defmodule Brando.Sites.Redirect.ValidSource do
  @moduledoc """
  Checks that a redirect's `from` compiles as a pattern. Every 404 in the
  redirect's language is matched against it.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    Ecto.Changeset.validate_change(changeset, :from, fn :from, from ->
      case compile(from) do
        {:ok, _regex} -> []
        :error -> [from: gettext("is not a valid pattern")]
      end
    end)
  end

  # Here, not in Brando.Sites.Redirects: the Blueprint uses this trait at
  # compile time, and Redirects would tie it to most of Brando.
  @doc """
  The pattern a redirect's `from` matches with: anchored at the start, each
  `:name` segment a named capture. `{:ok, regex}`, or `:error` if it does not
  compile.
  """
  @spec compile(String.t()) :: {:ok, Regex.t()} | :error
  def compile(from) when is_binary(from) do
    "^#{from}"
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> segment -> "(?<#{segment}>[a-z0-9\-\_]+)"
      segment -> segment
    end)
    |> Regex.compile()
    |> case do
      {:ok, regex} -> {:ok, regex}
      {:error, _reason} -> :error
    end
  end

  def compile(_from), do: :error
end
