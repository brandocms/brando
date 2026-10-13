defmodule Brando.Doctor.Checks.ModuleEntryPaths do
  @moduledoc """
  Module code that reads a multi module's entries the way Villain stored
  them, `{{ link.data.vars.url }}`. Since the blocks conversion an entry is a
  block with its vars and refs on it, `{{ link.vars.url }}`, and the old path
  renders nothing.

  `brando_219` rewrites the shapes it recognises (a loop over `entries`, a
  variable assigned an entry, a property path given to a filter); this lists
  what is left, and code written the old way since. It reads every Liquid
  module that is not a datasource module, whose `entries` are records rather
  than blocks, and reports each `.data.vars` or `.data.refs` in Liquid tags
  and output, or `"data.vars.…"` in quotes, with its line.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Doctor.Context
  alias Brando.Type.I18nString

  @liquid ~r/\{\{.*?\}\}|\{%.*?%\}/s
  @quoted ~r/('[^']*'|"[^"]*")/
  @path ~r/\.data\.(?:vars|refs)\b/
  @quoted_path ~r/^['"]data\.(?:vars|refs)\./

  @impl true
  def id, do: "module_entry_paths"

  @impl true
  def label, do: dgettext("doctor", "Module entry paths")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&modules/0)
    |> evaluate()
  end

  @doc """
  Turns `[{environment_label, [{module_name, module_id, code}]}]` into a
  result.
  """
  def evaluate(per_environment) do
    found =
      for {label, modules} <- per_environment,
          {name, id, code} <- modules,
          {line, text} <- scan(code),
          do: {label, name, id, line, text}

    case found do
      [] ->
        ok(dgettext("doctor", "no module reads its entries through .data.vars or .data.refs"))

      found ->
        modules = found |> Enum.uniq_by(fn {label, _, id, _, _} -> {label, id} end) |> length()

        warning(
          dngettext(
            "doctor",
            "%{count} module reads its entries through .data.vars or .data.refs, which renders nothing",
            "%{count} modules read their entries through .data.vars or .data.refs, which renders nothing",
            modules
          ),
          fix:
            dgettext(
              "doctor",
              "an entry's vars and refs are entry.vars and entry.refs since the blocks conversion: run brando_219 (mix brando.gen.migrations, mix brando.migrate) or edit the module code, then mix brando.entries.resave"
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
  The Liquid in `code` that reads `.data.vars` or `.data.refs`, as
  `[{line, liquid}]`.
  """
  @spec scan(String.t() | nil) :: [{pos_integer(), String.t()}]
  def scan(nil), do: []

  def scan(code) do
    @liquid
    |> Regex.scan(code, return: :index)
    |> Enum.filter(fn [{start, length}] -> legacy_path?(binary_part(code, start, length)) end)
    |> Enum.map(fn [{start, length}] ->
      line = code |> binary_part(0, start) |> String.split("\n") |> length()
      {line, code |> binary_part(start, length) |> String.replace(~r/\s+/, " ")}
    end)
  end

  defp legacy_path?(liquid) do
    @quoted
    |> Regex.split(liquid, include_captures: true)
    |> Enum.any?(fn part ->
      if String.starts_with?(part, ["'", "\""]),
        do: Regex.match?(@quoted_path, part),
        else: Regex.match?(@path, part)
    end)
  end

  defp modules do
    Brando.Repo.all(
      from m in Brando.Content.Module,
        where: is_nil(m.deleted_at),
        where: fragment("? IS NOT TRUE AND ? IS DISTINCT FROM 'heex'", m.datasource, m.type),
        where: fragment("? ~ 'data\\.(vars|refs)'", m.code),
        order_by: m.id,
        select: {m.name, m.id, m.code}
    )
    |> Enum.map(fn {name, id, code} -> {I18nString.get(name, nil) || "-", id, code} end)
  end
end
