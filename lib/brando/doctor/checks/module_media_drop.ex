defmodule Brando.Doctor.Checks.ModuleMediaDrop do
  @moduledoc """
  Multi modules whose `media_drop` no longer fits their children
  (`Brando.Content.Module.media_drop_issue/2`): the child module was deleted
  or moved, its ref renamed or retyped, or the module is no longer multi.
  Their blocks show no drop zone, and the definition export leaves the
  setting out. The fix is choosing the child and ref again in the module's
  editor, or clearing them.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Module
  alias Brando.Doctor.Context

  @impl true
  def id, do: "module_media_drop"

  @impl true
  def label, do: dgettext("doctor", "Module media drop")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&stale/0)
    |> evaluate()
  end

  @doc "The modules of the current prefix with a stale `media_drop`: `[{name, uid, problem}]`."
  def stale do
    children = from(c in Module, where: is_nil(c.deleted_at), preload: :refs)

    from(m in Module,
      where: is_nil(m.deleted_at) and (not is_nil(m.media_drop_child) or not is_nil(m.media_drop_ref)),
      order_by: m.id,
      preload: [children: ^children]
    )
    |> Brando.Repo.all()
    |> Enum.flat_map(fn module ->
      case Module.media_drop_issue(module, module.children) do
        nil -> []
        issue -> [{module_name(module), module.uid, Module.translate_media_drop_issue(issue)}]
      end
    end)
  end

  @doc "Turns `[{environment_label, [{module_name, uid, problem}]}]` into a result."
  def evaluate(per_environment) do
    case for {label, modules} <- per_environment, module <- modules, do: {label, module} do
      [] ->
        ok(dgettext("doctor", "every media drop setting fits its module's children"))

      stale ->
        warning(
          dngettext(
            "doctor",
            "%{count} module with a media drop setting that no longer fits",
            "%{count} modules with media drop settings that no longer fit",
            length(stale)
          ),
          fix:
            dgettext(
              "doctor",
              "their blocks show no drop zone: choose the child module and ref again under Block modules, or clear them"
            ),
          items:
            Enum.map(stale, fn {label, {name, uid, problem}} ->
              Context.label_item(label, "#{name} (#{uid}): #{problem}")
            end)
        )
    end
  end

  defp module_name(%{name: name}) when is_map(name), do: Brando.Type.I18nString.get(name, nil) || "-"
  defp module_name(%{name: name}), do: to_string(name)
end
