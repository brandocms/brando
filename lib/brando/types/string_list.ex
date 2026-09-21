defmodule Brando.Type.StringList do
  @moduledoc """
  A list of short strings, stored as a JSON/array column.

  Casts from a list, from the indexed map a form submits, or from a
  comma-separated string — the shape `area_served` and `knows_about` had
  before they became lists — so a site whose identity config predates the
  change still loads. Blank entries are dropped and the rest trimmed.
  """
  use Ecto.Type

  @impl true
  def type, do: {:array, :string}

  @impl true
  def cast(nil), do: {:ok, []}
  def cast(list) when is_list(list), do: {:ok, normalize(list)}

  def cast(value) when is_binary(value) do
    {:ok, value |> String.split(",") |> normalize()}
  end

  def cast(%{} = indexed) do
    values =
      indexed
      |> Enum.sort_by(fn {key, _} -> to_integer(key) end)
      |> Enum.map(fn {_, value} -> value end)

    {:ok, normalize(values)}
  end

  def cast(_), do: :error

  @impl true
  def load(value), do: cast(value)

  @impl true
  def dump(nil), do: {:ok, []}
  def dump(list) when is_list(list), do: {:ok, normalize(list)}
  def dump(value) when is_binary(value), do: cast(value)
  def dump(_), do: :error

  @impl true
  def equal?(a, b), do: normalize(List.wrap(a)) == normalize(List.wrap(b))

  @doc "Trims every entry and drops the blank ones."
  @spec normalize([term()]) :: [String.t()]
  def normalize(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp to_integer(key) when is_integer(key), do: key

  defp to_integer(key) when is_binary(key) do
    case Integer.parse(key) do
      {int, ""} -> int
      _ -> 0
    end
  end

  defp to_integer(_), do: 0
end
