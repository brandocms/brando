defmodule BrandoAdmin.Components.Form.EntryHeader do
  @moduledoc """
  The entry editor's heading: a breadcrumb with the content type, the entry's
  own title, and its status as one compact control beside it.

  The heading follows the saved entry, not the title field: it changes when
  the entry is saved, so typing costs no server work. The status control is
  part of the entry form (its radios name the form with `form=`), so it posts
  the same field the blueprint's `:status` input did.

  The data helpers (`crumbs/2`, `title/2`, `status_options/3`, `lift_status/1`)
  are pure, so the form can compute them once and tests can call them alone.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Blueprint.Forms.Fieldset
  alias Brando.Blueprint.Forms.Input, as: BlueprintInput

  @statuses [:draft, :pending, :published, :disabled]
  # A status input with any other option (`show_if`, `superuser`, …) keeps
  # its place in the form, where those options apply.
  @liftable_opts [:label, :instructions]

  @doc """
  The breadcrumb above the heading: the content type's icon and listing name
  (linked to the listing where there is one), and the blueprint's own name when
  it calls its entries something else (Projects · Case). The entry's language
  follows them (`language/1`).
  """
  def crumbs(schema) do
    listing = listing_name(schema)
    singular = Brando.Blueprint.get_singular(schema)

    %{
      icon: Brando.Blueprint.get_icon(schema),
      listing: listing,
      listing_url: listing_url(schema),
      kind: kind(singular, own_names(schema))
    }
  end

  # The name the sidebar gives a blueprint's listing (`BrandoAdmin.Menu`).
  defp listing_name(schema) do
    %{domain: domain, schema: schema_name, plural: plural} = schema.__naming__()
    msgid = Brando.Utils.humanize(plural, :downcase)

    schema.__modules__().gettext
    |> Gettext.dgettext(String.downcase("#{domain}_#{schema_name}"), msgid)
    |> String.capitalize()
  rescue
    _ -> Brando.Blueprint.get_plural(schema)
  end

  @doc """
  The blueprint's own name for its entries, when it is not just its schema's
  name or a translation of it: a project blueprint whose entries are cases
  shows "Case"; a page blueprint ("page", "side") shows nothing.
  """
  def kind(singular, own_names) do
    if String.downcase(singular) in Enum.map(own_names, &String.downcase/1), do: nil, else: singular
  end

  defp own_names(schema) do
    %{domain: domain, schema: schema_name, singular: own} = schema.__naming__()
    [own, Gettext.dgettext(schema.__modules__().gettext, String.downcase("#{domain}_#{schema_name}"), own)]
  rescue
    _ -> []
  end

  defp listing_url(schema) do
    schema.__admin_route__(:list, [schema.__modules__().admin_list_view])
  rescue
    _ -> nil
  end

  @doc "The entry's language for the breadcrumb, `EN`, or nil."
  def language(%{language: language}) when language not in [nil, ""],
    do: language |> to_string() |> String.upcase()

  def language(_entry), do: nil

  @doc """
  The heading: the entry's title as its identifier renders it, or "New case"
  for an entry that has not been saved.
  """
  def title(schema, %{id: id} = entry) when not is_nil(id) do
    identifier_title(schema, entry) || field_title(entry) || Brando.Blueprint.get_singular(schema)
  end

  def title(schema, _entry), do: new_title(schema)

  @doc "\"New case\": the blueprint's own name for an entry not yet saved."
  def new_title(schema) do
    gettext("New %{type}", type: String.downcase(Brando.Blueprint.get_singular(schema)))
  end

  defp identifier_title(schema, entry) do
    if function_exported?(schema, :__has_identifier__, 0) and schema.__has_identifier__() do
      case schema.__identifier__(entry, skip_cover: true) do
        %{title: title} when is_binary(title) and title != "" -> title
        _ -> nil
      end
    end
  rescue
    _ -> nil
  end

  defp field_title(entry) do
    Enum.find_value([:title, :name, :key], fn field ->
      case Map.get(entry, field) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  @doc """
  The status choices with their labels. Mirrors the publishing rule of
  `Brando.Authorization.Engine`: without the publish permission, a user can't
  publish an entry, and can't change a published one, so those choices are
  disabled rather than refused on save.
  """
  def status_options(saved_status, can_publish?, statuses \\ @statuses) do
    saved = normalize(saved_status)

    Enum.map(statuses, fn status ->
      %{
        value: to_string(status),
        label: status_label(status),
        disabled: not can_publish? and status != saved and (status == :published or saved == :published)
      }
    end)
  end

  defp normalize(status) when is_atom(status), do: status
  defp normalize(status) when is_binary(status), do: String.to_existing_atom(status)

  @doc "A status's label, from Gettext."
  def status_label(:draft), do: gettext("Draft")
  def status_label(:pending), do: gettext("Pending")
  def status_label(:published), do: gettext("Published")
  def status_label(:disabled), do: gettext("Deactivated")
  def status_label(status) when is_binary(status), do: status |> String.to_existing_atom() |> status_label()
  def status_label(_), do: gettext("Not set")

  @doc """
  Takes a plain `:status` input out of the form's tabs, for the heading to
  show instead. Returns `{tabs, field}`, where `field` is the input's name, or
  `{tabs, nil}` when there is none to lift. A fieldset left empty goes too.
  """
  def lift_status(tabs) do
    case Enum.find_value(tabs, &liftable_status/1) do
      nil -> {tabs, nil}
      %BlueprintInput{} = input -> {Enum.map(tabs, &drop_input(&1, input)), input.name}
    end
  end

  defp liftable_status(%{fields: fieldsets}) do
    Enum.find_value(fieldsets, fn
      %Fieldset{superuser: false, fields: fields} ->
        Enum.find(fields, fn
          %BlueprintInput{type: :status, opts: opts} -> Keyword.keys(opts || []) -- @liftable_opts == []
          _ -> false
        end)

      _ ->
        nil
    end)
  end

  defp drop_input(tab, input) do
    fieldsets =
      Enum.flat_map(tab.fields, fn
        %Fieldset{fields: fields} = fieldset ->
          if input in fields do
            remaining = List.delete(fields, input)

            if remaining == [] and is_nil(fieldset.label) and is_nil(fieldset.component),
              do: [],
              else: [%{fieldset | fields: remaining}]
          else
            [fieldset]
          end

        other ->
          [other]
      end)

    %{tab | fields: fieldsets}
  end

  attr :crumbs, :map, required: true
  attr :language, :string, default: nil
  attr :title, :string, default: nil
  slot :inner_block, doc: "Beside the title: the status control"

  def header(assigns) do
    ~H"""
    <header class="entry-header">
      <nav class="entry-breadcrumb" aria-label={gettext("Breadcrumb")}>
        <.icon name={@crumbs.icon} class="entry-breadcrumb-icon" />
        <%= if @crumbs.listing_url do %>
          <.link navigate={@crumbs.listing_url}>{@crumbs.listing}</.link>
        <% else %>
          <span>{@crumbs.listing}</span>
        <% end %>
        <span :if={@crumbs.kind} class="entry-breadcrumb-kind">{@crumbs.kind}</span>
        <span :if={@language} class="entry-breadcrumb-language">{@language}</span>
      </nav>
      <div class="entry-heading">
        <h1 :if={@title} data-testid="entry-title">{@title}</h1>
        {render_slot(@inner_block)}
      </div>
    </header>
    """
  end

  attr :id, :string, required: true
  attr :form_id, :string, required: true, doc: "The DOM id of the entry `<form>` the radios belong to"
  attr :name, :string, required: true, doc: "The field's input name, e.g. `project[status]`"
  attr :value, :any, required: true
  attr :options, :list, required: true

  @doc """
  The status as one control: a button with the status dot, its label and a
  chevron, opening the choices as radios of the entry form. Arrow keys move
  between them, Enter or a click chooses and closes, Escape closes
  (`Brando.FloatingDropdown`).
  """
  def status_control(assigns) do
    assigns =
      assign(assigns, :current, Enum.find(assigns.options, &(&1.value == to_string(assigns.value))))

    ~H"""
    <div
      id={@id}
      class="entry-status field-wrapper"
      phx-hook="Brando.FloatingDropdown"
      data-placement="bottom-start"
      data-choice-menu
    >
      <button
        type="button"
        class="entry-status-trigger"
        data-testid="status-trigger"
        data-status={@current && @current.value}
        popovertarget={"#{@id}-options"}
        aria-haspopup="true"
        aria-expanded="false"
        aria-label={gettext("Status: %{status}", status: (@current && @current.label) || status_label(nil))}
      >
        <.status_dot status={@current && @current.value} />
        <span class="entry-status-label">{(@current && @current.label) || status_label(nil)}</span>
        <.icon name="chevron-down" class="entry-status-chevron" />
      </button>
      <span class="entry-status-presence" data-field-presence={@name}>
        <span class="field-presence" phx-update="ignore" id={"#{@id}-field-presence"}></span>
      </span>
      <div
        id={"#{@id}-options"}
        class="entry-status-options"
        popover="auto"
        role="radiogroup"
        aria-label={gettext("Status")}
        data-testid="status-options"
      >
        <label :for={option <- @options} :key={option.value} class={["entry-status-option", option.disabled && "disabled"]}>
          <input
            type="radio"
            form={@form_id}
            id={"#{@id}-#{option.value}"}
            name={@name}
            value={option.value}
            checked={option.value == to_string(@value)}
            disabled={option.disabled}
          />
          <.status_dot status={option.value} />
          <span>{option.label}</span>
          <.icon name="check" class="entry-status-check" />
        </label>
      </div>
    </div>
    """
  end

  attr :status, :string, default: nil

  defp status_dot(assigns) do
    ~H"""
    <svg class="status-dot" aria-hidden="true" viewBox="0 0 12 12"><circle class={@status} r="6" cx="6" cy="6" /></svg>
    """
  end
end
