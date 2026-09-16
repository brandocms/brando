defmodule BrandoAdmin.Components.TextDiff do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  @max_characters 12_000
  @max_lines 400

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :before, :string, required: true
  attr :after, :string, required: true
  attr :description, :string, default: nil
  attr :note, :string, default: nil
  attr :empty_text, :string, default: nil
  attr :monospace, :boolean, default: false

  @doc """
  A bounded line diff for plain text. Callers supply any serialization and
  contextual labels; no text is interpreted as HTML. Parent layouts own spacing.
  """

  def diff(assigns) do
    assigns = assign(assigns, :comparison, compare(assigns.before, assigns.after))

    ~H"""
    <section id={@id} class={["admin-text-diff", @monospace && "is-code"]} aria-labelledby={@id <> "-title"}>
      <header class="admin-text-diff-heading">
        <div>
          <h4 id={@id <> "-title"}>{@label}</h4>
          <p>
            {@description || dgettext("admin_diff", "Before → after")}
          </p>
        </div>
        <div class="text-diff-counts">
          <span :if={@comparison.removed > 0} class="is-removed">
            <span aria-hidden="true">−</span>{dngettext(
              "admin_diff",
              "%{count} line removed",
              "%{count} lines removed",
              @comparison.removed
            )}
          </span>
          <span :if={@comparison.added > 0} class="is-added">
            <span aria-hidden="true">+</span>{dngettext(
              "admin_diff",
              "%{count} line added",
              "%{count} lines added",
              @comparison.added
            )}
          </span>
          <span :if={@comparison.added == 0 && @comparison.removed == 0} class="is-unchanged">
            {dgettext("admin_diff", "No text changes in this preview")}
          </span>
        </div>
      </header>
      <div
        :if={@comparison.rows != []}
        class="text-diff-lines"
        role="region"
        aria-label={dgettext("admin_diff", "Text changes in %{field}", field: @label)}
        tabindex="0"
      >
        <div :for={row <- @comparison.rows} class={["text-diff-line", "is-#{row.kind}"]}>
          <span class="text-diff-number" aria-hidden="true">{row.before}</span>
          <span class="text-diff-number" aria-hidden="true">{row.after}</span>
          <span class="text-diff-marker" aria-hidden="true">{marker(row.kind)}</span>
          <span class="sr-only">{line_label(row.kind)}</span>
          <del :if={row.kind == :del} class="text-diff-text">{row.text}</del>
          <ins :if={row.kind == :ins} class="text-diff-text">{row.text}</ins>
          <span :if={row.kind == :eq} class="text-diff-text">{row.text}</span>
        </div>
      </div>
      <p :if={@comparison.rows == []} class="text-diff-empty">{@empty_text || dgettext("admin_diff", "No content")}</p>
      <footer :if={@note || @comparison.truncated?}>
        <p :if={@comparison.truncated?} class="text-diff-truncated">
          {dgettext("admin_diff", "Preview shortened. More content exists beyond the lines shown.")}
        </p>
        <p :if={@note}>{@note}</p>
      </footer>
    </section>
    """
  end

  # Compare bounded text previews, never markup. HEEx escapes every displayed line.
  # Blank sides are empty lists so the empty-state label never becomes a deletion.
  def compare(before, after_text) do
    {before_lines, before_truncated?} = lines(before)
    {after_lines, after_truncated?} = lines(after_text)

    {groups, _} =
      before_lines
      |> List.myers_difference(after_lines)
      |> Enum.map_reduce({1, 1}, fn {kind, lines}, position ->
        Enum.map_reduce(lines, position, fn text, {old, new} ->
          row = %{kind: kind, text: text, before: if(kind != :ins, do: old), after: if(kind != :del, do: new)}
          {row, {old + if(kind == :ins, do: 0, else: 1), new + if(kind == :del, do: 0, else: 1)}}
        end)
      end)

    rows = List.flatten(groups)

    %{
      rows: rows,
      added: Enum.count(rows, &(&1.kind == :ins)),
      removed: Enum.count(rows, &(&1.kind == :del)),
      truncated?: before_truncated? || after_truncated?
    }
  end

  defp lines(""), do: {[], false}

  defp lines(text) do
    preview = String.slice(text, 0, @max_characters)
    lines = String.split(preview, ~r/\r\n|\n|\r/)
    {Enum.take(lines, @max_lines), preview != text || length(lines) > @max_lines}
  end

  defp marker(:ins), do: "+"
  defp marker(:del), do: "−"
  defp marker(:eq), do: " "
  defp line_label(:ins), do: dgettext("admin_diff", "Added:")
  defp line_label(:del), do: dgettext("admin_diff", "Removed:")
  defp line_label(:eq), do: dgettext("admin_diff", "Unchanged:")
end
