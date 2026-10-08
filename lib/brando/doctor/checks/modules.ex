defmodule Brando.Doctor.Checks.Modules do
  @moduledoc """
  Blocks on outdated module versions: blocks whose `module_version` is behind
  their module's, found as `Brando.Content.Blocks.list_stale_block_ids/2`
  finds them. They still render, but may hold refs or vars the module no
  longer defines. The fix is resolving those (`Brando.Content.StaleBlocks`),
  in the admin or with `mix brando.modules resolve`; a refresh alone does
  not.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.Blocks
  alias Brando.Doctor.Context

  @impl true
  def id, do: "modules"

  @impl true
  def label, do: dgettext("doctor", "Modules")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(fn ->
      Enum.map(Blocks.count_stale_blocks_by_module(), fn {module, count} -> {module_name(module), module.uid, count} end)
    end)
    |> evaluate()
  end

  @doc "Turns `[{environment_label, [{module_name, uid, stale_count}]}]` into a result."
  def evaluate(per_environment) do
    stale = for {label, modules} <- per_environment, {name, uid, count} <- modules, do: {label, name, uid, count}

    case stale do
      [] ->
        ok(dgettext("doctor", "all blocks on their module's current version"))

      stale ->
        blocks = stale |> Enum.map(&elem(&1, 3)) |> Enum.sum()

        warning(
          dngettext(
            "doctor",
            "%{count} block on an outdated module version",
            "%{count} blocks on outdated module versions",
            blocks
          ),
          fix:
            dgettext(
              "doctor",
              "they hold refs or vars their module no longer defines: resolve them under Block modules, or with mix brando.modules resolve --uid UID --user ID"
            ),
          link: {"/admin/config/content/modules/stale-blocks", dgettext("doctor", "Resolve blocks")},
          items:
            Enum.map(stale, fn {label, name, uid, count} ->
              Context.label_item(
                label,
                dngettext("doctor", "%{module} (%{uid}): %{count} block", "%{module} (%{uid}): %{count} blocks", count,
                  module: name,
                  uid: uid
                )
              )
            end)
        )
    end
  end

  defp module_name(%{name: name}) when is_map(name), do: Brando.Type.I18nString.get(name, nil) || "-"
  defp module_name(%{name: name}), do: to_string(name)
end
