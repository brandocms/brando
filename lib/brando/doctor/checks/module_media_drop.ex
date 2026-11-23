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

  alias Brando.Content.{Module, SharedLibrary}
  alias Brando.Doctor.Context
  alias Brando.Sites.Site
  alias Brando.Tenant

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
      case Module.media_drop_issue(module, fn -> children(module) end) do
        nil -> []
        issue -> [{module_name(module), module.uid, Module.translate_media_drop_issue(issue)}]
      end
    end)
  end

  # A shared-library module customized here holds the setting but no children
  # of its own: the block editor offers it the library module's children, or
  # their overrides here, as the site has them (`SharedLibrary.list_available/3`)
  defp children(%{source_module_id: source_id}) when not is_nil(source_id) do
    with prefix when is_binary(prefix) <- Tenant.current_prefix(),
         site_key when is_binary(site_key) <- Tenant.current_site_key(),
         %Site{} = site <- Tenant.Registry.get_site_by_key(site_key) do
      :module
      |> SharedLibrary.list_available(site, prefix)
      |> Enum.filter(&(&1.parent_id == source_id))
    else
      _no_site -> []
    end
  end

  defp children(module), do: module.children

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
