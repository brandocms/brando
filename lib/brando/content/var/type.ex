defmodule Brando.Content.Var.Type do
  @moduledoc """
  The type of a `Brando.Content.Var`, stored as a string.

  `:rich_text` was called `:html` before 0.55. The old name is still read
  wherever a type comes in (params, module exports, content transfer files,
  revisions, rows a project has not migrated yet) and is always written as
  `rich_text`.
  """
  use Ecto.Type

  @types [
    :boolean,
    :string,
    :text,
    :rich_text,
    :image,
    :video,
    :gallery,
    :datetime,
    :color,
    :select,
    :file,
    :link,
    :form,
    :date
  ]
  @aliases %{html: :rich_text}
  @by_name Map.new(@types, &{Atom.to_string(&1), &1})
           |> Map.merge(Map.new(@aliases, fn {old, new} -> {Atom.to_string(old), new} end))

  @doc "The var types, by their current names."
  def values, do: @types

  @doc """
  The current name of a var type given as an atom or a string, `:html`
  included, or `nil` for an unknown type.
  """
  def normalize(type) when type in @types, do: type
  def normalize(type) when is_atom(type), do: Map.get(@aliases, type)
  def normalize(type) when is_binary(type), do: Map.get(@by_name, type)
  def normalize(_), do: nil

  @doc """
  `term` with each var in it typed `:html`, as a struct decoded from before
  0.55 holds it (a pending translation's entry), typed `:rich_text`.
  """
  def rename_in(%{__struct__: Brando.Content.Var, type: :html} = var), do: %{var | type: :rich_text}

  def rename_in(%{__struct__: module} = struct)
      when module in [DateTime, NaiveDateTime, Date, Time, Decimal, Ecto.Association.NotLoaded, Ecto.Schema.Metadata],
      do: struct

  def rename_in(%{__struct__: _} = struct),
    do:
      struct |> Map.from_struct() |> Enum.reduce(struct, fn {key, value}, acc -> Map.put(acc, key, rename_in(value)) end)

  def rename_in(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, rename_in(value)} end)
  def rename_in(list) when is_list(list), do: Enum.map(list, &rename_in/1)
  def rename_in(other), do: other

  @impl true
  def type, do: :string

  @impl true
  def cast(value) do
    case normalize(value) do
      nil -> :error
      type -> {:ok, type}
    end
  end

  @impl true
  def load(value) when is_binary(value), do: cast(value)
  def load(_), do: :error

  @impl true
  def dump(value) do
    case normalize(value) do
      nil -> :error
      type -> {:ok, Atom.to_string(type)}
    end
  end
end
