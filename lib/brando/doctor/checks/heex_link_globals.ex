defmodule Brando.Doctor.Checks.HeexLinkGlobals do
  @moduledoc """
  HEEx module and container code that uses a link global as a string.

  Since 0.55 a HEEx template reads a link global in `@globals` as its
  `Brando.Content.Var`, not its URL, so `<.entry_link var={...} />` has its
  text and target. Printing it, interpolating it, `:if` and `||` work as they
  did with the URL. Joining it with `<>`, comparing it or passing it to a
  function such as `String.replace/3` does not: those raise.

  This reads every HEEx module and container that mentions `globals` and
  reports, with its line, each `@globals["set"]["key"]` or
  `get_in(@globals, ["set", "key"])` naming a link global that is not the
  whole of an expression (`{...}`, `<%= ... %>`) or an operand of `&&`, `||`,
  `!`, `not`, `and`, `or`, `if` or `unless`. It reads the text, not the code,
  so a use it lists may be fine, and a global reached through a variable
  (`footer = @globals["footer"]`) is not seen.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Doctor.Context
  alias Brando.Type.I18nString

  @reference ~r/@globals\[\s*"([^"]+)"\s*\]\s*\[\s*"([^"]+)"\s*\]|get_in\(\s*@globals\s*,\s*\[\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\]\s*\)/
  @before_ok ["{", "<%=", "&&", "||", "!"]
  @before_word ~r/\b(?:not|and|or|if|unless)$/
  @after_ok ["}", "%>", "&&", "||"]
  @after_word ~r/^(?:and|or|do)\b/

  @impl true
  def id, do: "heex_link_globals"

  @impl true
  def label, do: dgettext("doctor", "Link globals in HEEx")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(fn -> {link_globals(), templates()} end)
    |> Enum.map(fn {label, {link_globals, templates}} ->
      {label, for({name, id, code} <- templates, do: {name, id, scan(code, link_globals)})}
    end)
    |> evaluate()
  end

  @doc """
  Turns `[{environment_label, [{template_name, id, [{line, code}]}]}]` into
  a result.
  """
  def evaluate(per_environment) do
    found =
      for {label, templates} <- per_environment,
          {name, id, uses} <- templates,
          {line, text} <- uses,
          do: {label, name, id, line, text}

    case found do
      [] ->
        ok(dgettext("doctor", "no HEEx template uses a link global as a string"))

      found ->
        templates = found |> Enum.uniq_by(fn {label, name, id, _, _} -> {label, name, id} end) |> length()

        warning(
          dngettext(
            "doctor",
            "%{count} HEEx template uses a link global as a string, which raises since link globals are vars",
            "%{count} HEEx templates use a link global as a string, which raises since link globals are vars",
            templates
          ),
          fix:
            dgettext(
              "doctor",
              "where the template joins, compares or transforms the global, wrap it in Brando.Villain.Filters.link_url/1; <.entry_link var={...} />, :if and printing it need no change"
            ),
          link: {"/admin/config/content/modules", dgettext("doctor", "Open block modules")},
          items:
            Enum.map(found, fn {label, name, id, line, text} ->
              Context.label_item(
                label,
                dgettext("doctor", "%{module} (#%{id}), line %{line}: %{code}",
                  module: name,
                  id: id,
                  line: line,
                  code: text
                )
              )
            end)
        )
    end
  end

  @doc """
  The lines of `code` that use a global in `link_globals`, a set of
  `{set_key, key}`, as a string, as `[{line, line_text}]`.
  """
  @spec scan(String.t() | nil, MapSet.t({String.t(), String.t()})) :: [{pos_integer(), String.t()}]
  def scan(nil, _link_globals), do: []

  def scan(code, link_globals) do
    @reference
    |> Regex.scan(code, return: :index)
    |> Enum.filter(fn [{start, length} | keys] ->
      MapSet.member?(link_globals, global_key(code, keys)) and not whole_or_truthy?(code, start, length)
    end)
    |> Enum.map(fn [{start, _} | _] ->
      line = code |> binary_part(0, start) |> String.split("\n") |> length()
      {line, code |> String.split("\n") |> Enum.at(line - 1) |> String.trim()}
    end)
    |> Enum.uniq()
  end

  # The bracket form fills the first two groups, `get_in` the last two
  defp global_key(code, keys) do
    case Enum.reject(keys, &match?({-1, _}, &1)) do
      [{set_start, set_length}, {key_start, key_length}] ->
        {binary_part(code, set_start, set_length), binary_part(code, key_start, key_length)}

      _ ->
        nil
    end
  end

  defp whole_or_truthy?(code, start, length) do
    before = code |> binary_part(0, start) |> String.trim_trailing()
    rest = code |> binary_part(start + length, byte_size(code) - start - length) |> String.trim_leading()

    (String.ends_with?(before, @before_ok) or Regex.match?(@before_word, before)) and
      (String.starts_with?(rest, @after_ok) or Regex.match?(@after_word, rest))
  end

  defp link_globals do
    Brando.Repo.all(
      from v in Brando.Content.Var,
        join: s in assoc(v, :global_set),
        where: v.type == :link,
        distinct: true,
        select: {s.key, v.key}
    )
    |> MapSet.new()
  end

  defp templates do
    modules =
      Brando.Repo.all(
        from m in Brando.Content.Module,
          where: is_nil(m.deleted_at) and m.type == :heex,
          where: fragment("? ~ 'globals'", m.code),
          order_by: m.id,
          select: {m.name, m.id, m.code}
      )

    containers =
      Brando.Repo.all(
        from c in Brando.Content.Container,
          where: is_nil(c.deleted_at) and c.type == :heex,
          where: fragment("? ~ 'globals'", c.code),
          order_by: c.id,
          select: {c.name, c.id, c.code}
      )

    Enum.map(modules, fn {name, id, code} -> {I18nString.get(name, nil) || "-", id, code} end) ++
      Enum.map(containers, fn {name, id, code} ->
        {dgettext("doctor", "container %{name}", name: name), id, code}
      end)
  end
end
