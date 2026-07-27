defmodule Brando.Content.Var.Layout do
  @moduledoc """
  Derives the editor layout of a set of vars.

  A var stores three layout facts and nothing else:

    * `sequence`  — its position in one flat list
    * `width`     — how much of a 12-unit row it claims
    * `new_row`   — whether a row break happens in front of it

  Rows are **derived** from those by packing left to right; they are never
  stored. That keeps deletes, inserts and reorders from being able to corrupt
  the layout — there is no row index to renumber and no separate structure to
  keep in sync with the var list.

  Widths come in two kinds:

    * fixed (`:full`, `:half`, `:third`, `:fourth`) claim 12, 6, 4 and 3 units
    * flexible (`:auto`, `:fill`) claim no fixed measure — `:auto` renders at
      its content width, `:fill` absorbs whatever units are left in the row

  A flexible slot still reserves `#{2}` units for packing purposes, so a row
  cannot accept more slots than it can actually display.
  """

  alias Brando.Content.Var

  @row_units 12
  @max_slots 4
  @min_flex_units 2
  @fixed_units %{full: 12, half: 6, third: 4, fourth: 3}
  @flex_widths [:auto, :fill]

  @type width :: :full | :half | :third | :fourth | :auto | :fill
  @type placement :: :content | :config | :hidden

  @doc "Total units available in a row."
  def row_units, do: @row_units

  @doc "Maximum number of vars a single row may hold."
  def max_slots, do: @max_slots

  @doc "All widths, fixed first."
  def widths, do: Map.keys(@fixed_units) ++ @flex_widths

  @doc "Fixed widths, in descending size."
  def fixed_widths, do: [:full, :half, :third, :fourth]

  @doc "Widths whose measure is decided at render time."
  def flex_widths, do: @flex_widths

  @doc """
  Whether `width` is sized at render time rather than claiming fixed units.

      iex> Brando.Content.Var.Layout.flex?(:fill)
      true

      iex> Brando.Content.Var.Layout.flex?(:half)
      false
  """
  def flex?(width) when is_binary(width), do: flex?(safe_atom(width))
  def flex?(width), do: width in @flex_widths

  @doc """
  Units `width` claims when packing a row.

      iex> Brando.Content.Var.Layout.unit_cost(:third)
      4

      iex> Brando.Content.Var.Layout.unit_cost(:auto)
      2
  """
  def unit_cost(width) when is_binary(width), do: unit_cost(safe_atom(width))
  def unit_cost(width) when width in @flex_widths, do: @min_flex_units
  def unit_cost(width), do: Map.get(@fixed_units, width, @row_units)

  @doc """
  Units already claimed by `vars`.

      iex> Brando.Content.Var.Layout.used_units([%{width: :half}, %{width: :fourth}])
      9
  """
  def used_units(vars), do: Enum.reduce(vars, 0, &(unit_cost(width_of(&1)) + &2))

  @doc """
  Units still free in a row holding `vars`.

      iex> Brando.Content.Var.Layout.free_units([%{width: :half}])
      6
  """
  def free_units(vars), do: @row_units - used_units(vars)

  @doc """
  Whether a row holding `vars` can take one more slot of `width`.

  Both the unit budget and the slot count have to allow it.
  """
  def fits?(vars, width) do
    length(vars) < @max_slots and used_units(vars) + unit_cost(width) <= @row_units
  end

  @doc """
  Packs `vars` into rows.

  Vars are consumed in the order given — callers pass them already sorted by
  `sequence`, which is how they come back from the database. A new row starts
  when the var asks for one, when the current row is full, or when the next
  var would overflow the unit budget.

      iex> Brando.Content.Var.Layout.pack([
      ...>   %{key: "a", width: :half, new_row: false},
      ...>   %{key: "b", width: :half, new_row: false},
      ...>   %{key: "c", width: :full, new_row: false}
      ...> ]) |> Enum.map(fn row -> Enum.map(row, & &1.key) end)
      [["a", "b"], ["c"]]

      iex> Brando.Content.Var.Layout.pack([
      ...>   %{key: "a", width: :half, new_row: false},
      ...>   %{key: "b", width: :half, new_row: true}
      ...> ]) |> Enum.map(fn row -> Enum.map(row, & &1.key) end)
      [["a"], ["b"]]
  """
  def pack(vars) do
    vars
    |> Enum.reduce([], fn var, rows ->
      case rows do
        [] ->
          [[var]]

        [current | rest] ->
          if breaks_row?(var, current) do
            [[var], current | rest]
          else
            [[var | current] | rest]
          end
      end
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
  end

  defp breaks_row?(var, current_row) do
    new_row?(var) or not fits?(current_row, width_of(var))
  end

  @doc """
  Packs the vars of `placement` into rows, ignoring the rest.

  Vars are sorted by `sequence` first so callers can hand over an unsorted
  association.
  """
  def pack_placement(vars, placement) do
    vars
    |> Enum.filter(&(placement_of(&1) == placement))
    |> Enum.sort_by(&(Map.get(&1, :sequence) || 0))
    |> pack()
  end

  @doc """
  Turns a row structure back into flat `sequence` / `new_row` / `placement`
  attributes, keyed by var key.

  This is the inverse of `pack/1` and the only thing the layout editor needs to
  send: the browser reports which keys ended up in which row, the server
  derives every stored field from that.

      iex> Brando.Content.Var.Layout.flatten(%{content: [["a", "b"], ["c"]]})
      %{
        "a" => %{sequence: 0, new_row: true, placement: :content},
        "b" => %{sequence: 1, new_row: false, placement: :content},
        "c" => %{sequence: 2, new_row: true, placement: :content}
      }
  """
  def flatten(rows_by_placement) do
    {attrs, _} =
      Enum.reduce([:content, :config, :hidden], {%{}, 0}, fn placement, acc ->
        rows_by_placement
        |> Map.get(placement, [])
        |> Enum.reduce(acc, fn row, {attrs, sequence} ->
          row
          |> Enum.with_index()
          |> Enum.reduce({attrs, sequence}, fn {key, index}, {attrs, sequence} ->
            entry = %{sequence: sequence, new_row: index == 0, placement: placement}
            {Map.put(attrs, key, entry), sequence + 1}
          end)
        end)
      end)

    attrs
  end

  @doc """
  Layout attributes for every var, given new rows for one surface only.

  The layout editor shows one surface at a time, so a drop only describes that
  surface. The surfaces it did not describe are re-derived from `vars` and
  merged in, which keeps `sequence` a single continuous ordering across all
  three rather than three overlapping ranges.

  Keys in `rows` that no var claims are ignored — the DOM is not the authority
  on which vars exist.

      iex> vars = [
      ...>   %{key: "a", width: :full, new_row: true, placement: :content, sequence: 0},
      ...>   %{key: "b", width: :full, new_row: true, placement: :config, sequence: 1}
      ...> ]
      iex> attrs = Brando.Content.Var.Layout.merge_surface(vars, :content, [["a"]])
      iex> {attrs["a"].placement, attrs["b"].placement}
      {:content, :config}
  """
  def merge_surface(vars, surface, rows) do
    known = MapSet.new(vars, &key_of/1)

    rows =
      rows
      |> Enum.map(fn row -> Enum.filter(row, &MapSet.member?(known, &1)) end)
      |> Enum.reject(&(&1 == []))

    [:content, :config, :hidden]
    |> Enum.reject(&(&1 == surface))
    |> Map.new(fn other ->
      {other,
       vars
       |> pack_placement(other)
       |> Enum.map(fn row -> Enum.map(row, &key_of/1) end)}
    end)
    |> Map.put(surface, rows)
    |> flatten()
  end

  @doc """
  Normalizes the `%{"content" => [["a", "b"]]}` payload a JS hook pushes into
  the atom-keyed shape `flatten/1` expects.

  Unknown placements are dropped rather than crashing on `String.to_atom/1`.
  """
  def normalize_payload(payload) when is_map(payload) do
    Map.new([:content, :config, :hidden], fn placement ->
      rows =
        payload
        |> Map.get(to_string(placement), [])
        |> Enum.map(fn row -> Enum.filter(row, &is_binary/1) end)
        |> Enum.reject(&(&1 == []))

      {placement, rows}
    end)
  end

  @doc """
  Applies `flatten/1` output to a list of var changesets or structs.

  Vars whose key is missing from the layout keep their current attributes —
  the layout editor only ever reports what it is showing, so a var belonging to
  another surface must not be reset.
  """
  def apply_layout(vars, layout_attrs) do
    Enum.map(vars, fn var ->
      key = key_of(var)

      case Map.get(layout_attrs, key) do
        nil -> var
        attrs -> put_layout(var, attrs)
      end
    end)
  end

  defp put_layout(%Ecto.Changeset{} = changeset, attrs),
    do: Ecto.Changeset.change(changeset, attrs)

  defp put_layout(%Var{} = var, attrs), do: struct(var, attrs)

  @doc """
  The width a var should be given when it is first placed.

  Booleans are narrow by nature, so they start at a quarter row rather than
  claiming a full line the way a text field reasonably does.
  """
  def default_width(:boolean), do: :fourth
  def default_width(type) when type in [:select, :color, :datetime, :date], do: :third
  def default_width(_type), do: :full

  # -- accessors tolerating structs, changesets and plain maps ---------------

  defp width_of(var), do: get(var, :width) || :full
  defp new_row?(var), do: get(var, :new_row) == true
  defp key_of(var), do: get(var, :key)

  @doc false
  def placement_of(var), do: get(var, :placement) || :content

  defp get(%Ecto.Changeset{} = changeset, field), do: Ecto.Changeset.get_field(changeset, field)
  defp get(var, field), do: Map.get(var, field)

  defp safe_atom(width) do
    String.to_existing_atom(width)
  rescue
    ArgumentError -> :full
  end
end
