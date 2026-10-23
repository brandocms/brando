defmodule BrandoAdmin.Components.Form.SavedElsewhere do
  @moduledoc false
  # The relations another editor's save changed while this editor had
  # changed them too (`relation_conflicts` in Form, "Saves by other
  # editors"). The form shows this editor's rows; the notice asks which to
  # keep.
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  attr :id, :string, required: true
  attr :conflicts, :list, required: true
  attr :schema, :atom, required: true
  attr :form_blueprint, :any, required: true
  attr :target, :any, required: true

  def notices(assigns) do
    assigns = assign(assigns, :labels, labels(assigns.schema, assigns.form_blueprint))

    ~H"""
    <div :if={@conflicts != []} id={@id} class="saved-elsewhere">
      <section
        :for={field <- @conflicts}
        id={"#{@id}-#{field}"}
        class="saved-elsewhere-notice"
        aria-label={gettext("Saved elsewhere")}
        data-testid="saved-elsewhere"
        data-field={field}
      >
        <div class="saved-elsewhere-content">
          <span class="saved-elsewhere-icon">
            <Brando.HTML.Icon.icon name="layers" class="saved-elsewhere-glyph" />
          </span>
          <div>
            <h2>
              {gettext("Another tab or editor saved %{field}", field: label(@labels, field))}
            </h2>
            <p>
              {gettext("You changed it too. The form shows your version, and saving replaces the saved one with it.")}
            </p>
          </div>
        </div>
        <div class="saved-elsewhere-actions">
          <button
            type="button"
            class="btn btn--primary"
            phx-click="keep_own_relation"
            phx-value-field={field}
            phx-target={@target}
          >
            {gettext("Keep my version")}
          </button>
          <button
            type="button"
            class="btn"
            phx-click="take_saved_relation"
            phx-value-field={field}
            phx-target={@target}
          >
            {gettext("Use the saved version")}
          </button>
        </div>
      </section>
    </div>
    """
  end

  defp label(labels, field), do: Map.get_lazy(labels, field, fn -> Phoenix.Naming.humanize(field) end)

  # The inputs' labels, translated in the schema's domain, as the form
  # shows them.
  defp labels(schema, %{tabs: tabs}) do
    naming = schema.__naming__()
    domain = String.downcase("#{naming.domain}_#{naming.schema}")
    gettext_module = schema.__modules__().gettext

    for tab <- tabs, fieldset <- tab.fields, input <- Map.get(fieldset, :fields, []), reduce: %{} do
      labels ->
        text = Map.get(input, :label) || (Map.get(input, :opts) || [])[:label]

        if is_binary(text),
          do: Map.put(labels, input.name, Gettext.dgettext(gettext_module, domain, text)),
          else: labels
    end
  end

  defp labels(_schema, _blueprint), do: %{}
end
