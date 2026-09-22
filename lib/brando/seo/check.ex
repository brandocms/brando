defmodule Brando.SEO.Check do
  @moduledoc """
  One verdict about one entry, produced by the content SEO audit.

  Built-in checks and a blueprint's own `__seo_checks__/1` return the same
  struct, so there is one rendering path and one scoring path.

    * `key` — stable identifier, used for grouping and i18n
    * `status` — `:pass`, `:warn`, `:fail`, or `:skip` when the check could
      not run (no sitemap generated yet, say); skipped checks do not count
    * `weight` — `:low`, `:normal` or `:critical`; see `weight_value/1`
    * `label` — short translated name
    * `hint` — what to do about it, translated; optional
    * `value` — what was measured, for display; optional
  """

  @type status :: :pass | :warn | :fail | :skip
  @type weight :: :low | :normal | :critical

  @type t :: %__MODULE__{
          key: atom(),
          status: status(),
          weight: weight(),
          label: String.t(),
          hint: String.t() | nil,
          value: term()
        }

  @enforce_keys [:key, :status, :label]
  defstruct key: nil, status: :pass, weight: :normal, label: nil, hint: nil, value: nil

  @doc "Numeric weight; a missing description outweighs a slightly long title."
  @spec weight_value(weight()) :: pos_integer()
  def weight_value(:low), do: 1
  def weight_value(:normal), do: 2
  def weight_value(:critical), do: 4

  @doc """
  Scores a list of checks from 0 to 100: passes earn their full weight, warnings
  half, failures nothing. Skipped checks are left out of both sides. `nil` when
  nothing could be scored.
  """
  @spec score([t()]) :: 0..100 | nil
  def score(checks) do
    scored = Enum.reject(checks, &(&1.status == :skip))

    case Enum.reduce(scored, {0, 0}, fn check, {earned, possible} ->
           weight = weight_value(check.weight)
           {earned + earned_for(check.status, weight), possible + weight}
         end) do
      {_, 0} -> nil
      {earned, possible} -> round(earned / possible * 100)
    end
  end

  defp earned_for(:pass, weight), do: weight
  defp earned_for(:warn, weight), do: weight / 2
  defp earned_for(_, _), do: 0
end
