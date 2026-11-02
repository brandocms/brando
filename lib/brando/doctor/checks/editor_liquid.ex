defmodule Brando.Doctor.Checks.EditorLiquid do
  @moduledoc """
  Stored refs and vars holding Liquid delimiters. What editors write prints as
  text, so Liquid in a text or Markdown ref, a caption or a var shows on the
  page as written. Anything meant to run belongs in the module's own code.

  It reads every ref and var, on blocks and on module definitions, leaving out
  SVG and HTML refs, which are superusers' templates and run their Liquid.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Doctor.Context

  @impl true
  def id, do: "editor_liquid"

  @impl true
  def label, do: dgettext("doctor", "Liquid in editor text")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&stored/0)
    |> evaluate()
  end

  @doc """
  Turns `[{environment_label, [{name, block_id, module_id}]}]` into a result.
  """
  def evaluate(per_environment) do
    found = for {label, stored} <- per_environment, item <- stored, do: {label, item}

    case found do
      [] ->
        ok(dgettext("doctor", "no ref or var holds Liquid"))

      found ->
        warning(
          dngettext(
            "doctor",
            "%{count} ref or var holds Liquid, which prints as text",
            "%{count} refs and vars hold Liquid, which prints as text",
            length(found)
          ),
          fix:
            dgettext(
              "doctor",
              "move what should run into the module's code, or edit the text if it should not show: Liquid in refs and vars is not run"
            ),
          items: Enum.map(found, fn {label, item} -> Context.label_item(label, item_text(item)) end)
        )
    end
  end

  defp item_text({name, nil, module_id}),
    do: dgettext("doctor", "%{name} on module #%{id}", name: name, id: module_id)

  defp item_text({name, block_id, _module_id}),
    do: dgettext("doctor", "%{name} on block #%{id}", name: name, id: block_id)

  defp stored do
    refs =
      Brando.Repo.all(
        from r in Ref,
          where: fragment("?::text ~ '\\{[{%]'", r.data),
          where: fragment("?->>'type' NOT IN ('svg', 'html')", r.data),
          order_by: r.id,
          select: {r.name, r.block_id, r.module_id}
      )

    vars =
      Brando.Repo.all(
        from v in Var,
          where: fragment("? ~ '\\{[{%]'", v.value),
          where: not is_nil(v.block_id) or not is_nil(v.module_id),
          order_by: v.id,
          select: {v.key, v.block_id, v.module_id}
      )

    refs ++ vars
  end
end
