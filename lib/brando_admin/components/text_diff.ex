defmodule BrandoAdmin.Components.TextDiff do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  @max_characters 12_000
  @max_lines 400

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :before, :any, required: true
  attr :after, :any, required: true
  attr :description, :string, default: nil
  attr :note, :string, default: nil
  attr :empty_text, :string, default: nil
  attr :monospace, :boolean, default: false

  @doc """
  A bounded line diff for plain text or lists of `%{text: text, key: identity}`.
  Optional line types (`:heading`, `:media`, `:detail`) provide visual hierarchy.
  A media line may include `preview: %{kind: kind, thumbnail: url, detail: text}`.
  Keys distinguish equal labels with different identities; they are never rendered.
  Callers supply serialization and contextual labels. All text is escaped.
  """

  def diff(assigns) do
    comparison = compare(assigns.before, assigns.after)
    assigns = assign(assigns, :comparison, Map.update!(comparison, :rows, &mark_changed_headings/1))

    ~H"""
    <section
      id={@id}
      class={["admin-text-diff", @monospace && "is-code"]}
      aria-labelledby={@id <> "-title"}
      data-changed={to_string(@comparison.added > 0 || @comparison.removed > 0)}
      data-truncated={to_string(@comparison.truncated?)}
    >
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
            {dgettext("admin_diff", "No changes in this preview")}
          </span>
        </div>
      </header>
      <div
        :if={@comparison.rows != []}
        class="text-diff-lines"
        role="region"
        aria-label={dgettext("admin_diff", "Changes in %{field}", field: @label)}
        tabindex="0"
      >
        <div
          :for={row <- @comparison.rows}
          class={[
            "text-diff-line",
            "is-#{row.kind}",
            row[:type] && "is-#{row.type}",
            row.change_heading? && "is-change-heading"
          ]}
        >
          <span class="text-diff-number" aria-hidden="true">{row.before}</span>
          <span class="text-diff-number" aria-hidden="true">{row.after}</span>
          <span class="text-diff-marker" aria-hidden="true">{marker(row.kind)}</span>
          <span class="sr-only">{line_label(row.kind)}</span>
          <del :if={row.kind == :del} class="text-diff-text"><.line_content row={row} /></del>
          <ins :if={row.kind == :ins} class="text-diff-text"><.line_content row={row} /></ins>
          <span :if={row.kind == :eq} class="text-diff-text"><.line_content row={row} /></span>
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

  attr :row, :map, required: true

  defp line_content(%{row: %{preview: preview}} = assigns) do
    assigns = assign(assigns, :preview, preview)

    ~H"""
    <span :if={@preview} class="text-diff-reference" data-kind={@preview.kind}>
      <img :if={@preview.thumbnail} src={@preview.thumbnail} alt="" loading="lazy" />
      <span :if={!@preview.thumbnail} class="text-diff-reference-icon" aria-hidden="true">
        <Brando.HTML.Icon.icon name={reference_icon(@preview.kind)} />
      </span>
      <span class="text-diff-reference-info">
        <span class="text-diff-reference-title">{@row.text}</span>
        <span class="text-diff-reference-detail">{@preview.detail}</span>
      </span>
    </span>
    """
  end

  defp line_content(assigns), do: ~H"{@row.text}"

  defp reference_icon(:image), do: "hero-photo"
  defp reference_icon(:video), do: "hero-film"
  defp reference_icon(:file), do: "hero-document"
  defp reference_icon(:entry), do: "hero-document-text"

  # A changes-only view still needs the field label, even when unchanged
  # paragraphs separate that label from its first changed line.
  defp mark_changed_headings(rows) do
    {rows, _} =
      rows
      |> Enum.reverse()
      |> Enum.map_reduce(false, fn row, changed? ->
        heading? = row[:type] == :heading
        next = if heading?, do: false, else: changed? || row.kind != :eq
        {Map.put(row, :change_heading?, heading? && changed?), next}
      end)

    Enum.reverse(rows)
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
        Enum.map_reduce(lines, position, fn line, {old, new} ->
          row = %{kind: kind, text: line.text, before: if(kind != :ins, do: old), after: if(kind != :del, do: new)}
          row = if line.type, do: Map.put(row, :type, line.type), else: row
          row = if line[:preview], do: Map.put(row, :preview, line.preview), else: row
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

  defp lines(text) when is_binary(text) do
    preview = String.slice(text, 0, @max_characters)
    lines = Enum.map(String.split(preview, ~r/\r\n|\n|\r/), &%{text: &1, key: nil, type: nil})
    {Enum.take(lines, @max_lines), preview != text || length(lines) > @max_lines}
  end

  defp lines(lines) when is_list(lines) do
    {preview, _, truncated?} =
      Enum.reduce_while(Enum.with_index(lines), {[], 0, false}, fn {line, index}, {acc, used, _} ->
        if index >= @max_lines || used >= @max_characters do
          {:halt, {acc, used, true}}
        else
          text = String.slice(line.text, 0, @max_characters - used)
          type = if line[:type] in [:heading, :media, :detail], do: line.type
          normalized = %{text: text, key: line[:key], type: type}
          normalized = if line[:preview], do: Map.put(normalized, :preview, line.preview), else: normalized
          next = {[normalized | acc], used + String.length(text) + 1, text != line.text}
          if text != line.text, do: {:halt, next}, else: {:cont, next}
        end
      end)

    {Enum.reverse(preview), truncated?}
  end

  defp marker(:ins), do: "+"
  defp marker(:del), do: "−"
  defp marker(:eq), do: " "
  defp line_label(:ins), do: dgettext("admin_diff", "Added:")
  defp line_label(:del), do: dgettext("admin_diff", "Removed:")
  defp line_label(:eq), do: dgettext("admin_diff", "Unchanged:")
end
