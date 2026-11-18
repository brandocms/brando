defmodule BrandoAdmin.Components.TextDiff do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.TextDiff.Highlight

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

  attr :highlight, :atom,
    default: nil,
    values: [nil, :liquid, :heex, :html],
    doc: "colours a template's or HTML's tags, attributes and expressions (implies monospace)"

  attr :context, :integer,
    default: nil,
    doc: "keeps this many unchanged lines around each change and folds the rest into a gap row"

  @doc """
  A bounded line diff for plain text or lists of `%{text: text, key: identity}`.
  Optional line types (`:heading`, `:media`, `:detail`) provide visual hierarchy.
  A media line may include `preview: %{kind: kind, thumbnail: url, detail: text}`.
  Keys distinguish equal labels with different identities; they are never rendered.
  Callers supply serialization and contextual labels. All text is escaped.
  """

  def diff(assigns) do
    comparison = compare(assigns.before, assigns.after)

    rows =
      comparison.rows
      |> mark_changed_headings()
      |> fold(assigns.context)
      |> highlight(assigns.highlight)

    assigns = assign(assigns, :comparison, %{comparison | rows: rows})

    ~H"""
    <section
      id={@id}
      class={["admin-text-diff", (@monospace || @highlight) && "is-code"]}
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
        <%= for row <- @comparison.rows do %>
          <div :if={row.kind == :gap} class="text-diff-gap">
            <span aria-hidden="true">⋯</span>
            <span>
              {dngettext("admin_diff", "%{count} unchanged line", "%{count} unchanged lines", row.count)}
            </span>
          </div>
          <div
            :if={row.kind != :gap}
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
        <% end %>
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

  defp line_content(%{row: %{tokens: tokens}} = assigns) do
    assigns = assign(assigns, :html, Highlight.to_html(tokens))
    ~H"{@html}"
  end

  defp line_content(assigns), do: ~H"{@row.text}"

  # Runs of unchanged lines longer than twice `context`, past the context
  # kept around each change, become one gap row
  defp fold(rows, nil), do: rows

  defp fold(rows, context) when is_integer(context) and context >= 0 do
    chunks = Enum.chunk_by(rows, &(&1.kind == :eq))
    last = length(chunks) - 1

    if Enum.all?(rows, &(&1.kind == :eq)) do
      rows
    else
      chunks
      |> Enum.with_index()
      |> Enum.flat_map(fn {chunk, index} -> fold_chunk(chunk, index == 0, index == last, context) end)
    end
  end

  # Before the first change only the lines leading up to it are kept, after
  # the last only those that follow it
  defp fold_chunk([%{kind: :eq} | _] = chunk, first?, last?, context) do
    head = if first?, do: 0, else: context
    tail = if last?, do: 0, else: context
    hidden = length(chunk) - head - tail

    if hidden > 1,
      do: Enum.take(chunk, head) ++ [%{kind: :gap, count: hidden}] ++ Enum.take(chunk, -tail),
      else: chunk
  end

  defp fold_chunk(chunk, _first?, _last?, _context), do: chunk

  defp highlight(rows, nil), do: rows

  defp highlight(rows, language),
    do: Enum.map(rows, &if(&1.kind == :gap, do: &1, else: Map.put(&1, :tokens, Highlight.tokens(&1.text, language))))

  defp reference_icon(:image), do: "image"
  defp reference_icon(:video), do: "film"
  defp reference_icon(:file), do: "file"
  defp reference_icon(:entry), do: "file-text"

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
        Enum.map_reduce(lines, position, &diff_row(kind, &1, &2))
      end)

    rows = List.flatten(groups)

    %{
      rows: rows,
      added: Enum.count(rows, &(&1.kind == :ins)),
      removed: Enum.count(rows, &(&1.kind == :del)),
      truncated?: before_truncated? || after_truncated?
    }
  end

  defp diff_row(kind, line, {old, new}) do
    row = %{kind: kind, text: line.text, before: if(kind != :ins, do: old), after: if(kind != :del, do: new)}
    row = if line.type, do: Map.put(row, :type, line.type), else: row
    row = if line[:preview], do: Map.put(row, :preview, line.preview), else: row
    {row, {old + if(kind == :ins, do: 0, else: 1), new + if(kind == :del, do: 0, else: 1)}}
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
          take_line(line, acc, used)
        end
      end)

    {Enum.reverse(preview), truncated?}
  end

  defp take_line(line, acc, used) do
    text = String.slice(line.text, 0, @max_characters - used)
    type = if line[:type] in [:heading, :media, :detail], do: line.type
    normalized = %{text: text, key: line[:key], type: type}
    normalized = if line[:preview], do: Map.put(normalized, :preview, line.preview), else: normalized
    next = {[normalized | acc], used + String.length(text) + 1, text != line.text}
    if text != line.text, do: {:halt, next}, else: {:cont, next}
  end

  defp marker(:ins), do: "+"
  defp marker(:del), do: "−"
  defp marker(:eq), do: " "
  defp line_label(:ins), do: dgettext("admin_diff", "Added:")
  defp line_label(:del), do: dgettext("admin_diff", "Removed:")
  defp line_label(:eq), do: dgettext("admin_diff", "Unchanged:")
end
