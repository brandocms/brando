defmodule Brando.Doctor.Checks.AltText do
  @moduledoc """
  Alt text coverage per content language, over the images
  `Brando.Images.AltText` would describe: processed, in the library, not SVG,
  and not taking their alt text from their entry.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.Images.AltText

  @impl true
  def id, do: "alt_text"

  @impl true
  def label, do: dgettext("doctor", "Alt text")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&AltText.missing_count_by_language/0)
    |> evaluate()
  end

  @doc "Turns `[{environment_label, %{language => {missing, total}}}]` into a result."
  def evaluate(per_environment) do
    totals =
      for {_label, counts} <- per_environment, {language, {missing, _total}} <- counts, reduce: %{} do
        acc -> Map.update(acc, language, missing, &(&1 + missing))
      end

    items =
      for {label, counts} <- per_environment, {language, {missing, total}} <- Enum.sort(counts) do
        Context.label_item(
          label,
          dgettext("doctor", "%{language}: %{missing} of %{total} without alt text (%{coverage} covered)",
            language: language,
            missing: missing,
            total: total,
            coverage: coverage(missing, total)
          )
        )
      end

    case for({language, missing} <- Enum.sort(totals), missing > 0, do: {language, missing}) do
      [] ->
        ok(dgettext("doctor", "every image has alt text"), items: items)

      lacking ->
        summary =
          Enum.map_join(lacking, ", ", fn {language, missing} ->
            dngettext(
              "doctor",
              "%{count} image without alt (%{language})",
              "%{count} images without alt (%{language})",
              missing,
              language: language
            )
          end)

        warning(summary,
          fix: dgettext("doctor", "Images → Alt text drafts it with AI, for review before saving"),
          link: {BrandoAdmin.Images.AltTextLive, dgettext("doctor", "Write alt text")},
          items: items
        )
    end
  end

  defp coverage(_missing, 0), do: "100%"
  defp coverage(missing, total), do: "#{div((total - missing) * 100, total)}%"
end
