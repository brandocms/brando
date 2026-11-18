defmodule Brando.Doctor.Checks.TranslationGalleries do
  @moduledoc """
  Independent translations that still point at a gallery record another
  language version of their group uses. A synchronized translation shows the
  source's galleries (its gallery variables and assets point at them), and
  **Make independent** gives it copies of its own. One made independent before
  it did keeps the shared record, so editing its gallery changes the other
  version too. `mix brando.translations.split_galleries` gives each its copies
  (`Brando.Translations.split_shared_galleries/3`).
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.Translations.SharedGalleries

  @impl true
  def id, do: "translation_galleries"

  @impl true
  def label, do: dgettext("doctor", "Translation galleries")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&SharedGalleries.independent_sharing/0)
    |> evaluate()
  end

  @doc "Turns `[{environment_label, found}]` into a result."
  def evaluate(per_environment) do
    case per_environment |> Enum.map(&length(elem(&1, 1))) |> Enum.sum() do
      0 ->
        ok(dgettext("doctor", "no independent translation shares a gallery with another language version"))

      total ->
        warning(
          dngettext(
            "doctor",
            "%{count} independent translation shares a gallery with another language version",
            "%{count} independent translations share a gallery with another language version",
            total
          ),
          fix:
            dgettext(
              "doctor",
              "editing such a gallery changes the other version too. Run mix brando.translations.split_galleries to give each translation its own copy"
            ),
          items:
            for {label, found} <- per_environment, {schema, id, language} <- found do
              Context.label_item(label, "#{inspect(schema)} ##{id} (#{language})")
            end
        )
    end
  end
end
