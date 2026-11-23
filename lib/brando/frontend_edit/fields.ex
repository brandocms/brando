defmodule Brando.FrontendEdit.Fields do
  @moduledoc """
  Entry fields in frontend edit mode: an entry's own fields (a title, an
  intro, a cover image) made editable where a template prints them.

  Brando cannot find these on its own: the same value is printed in visible
  text and in places a marker would break, like `<title>`, an `alt`
  attribute or JSON-LD. So the template marks the visible place:

      <.editable_field entry={@page} field={:intro} />

      <.editable entry={@project} field={:cover}>
        <.picture src={@project.cover} … />
      </.editable>

  or, in a Liquid module, `{% editable_field entry.intro %}` and
  `{% editable entry.cover %}…{% endeditable %}`. `render_rich_text/1` marks
  its field by itself.

  Outside edit mode these print exactly what they wrap. While annotating
  (see `Brando.FrontendEdit.annotating?/0`) they add markers: `[+:E<key>]`
  around a printed value, which the page updates as the field is edited
  (`[+:T<key>]` and `[+:R<key>]` for a subform row's field printed by its
  owner's forms, as text or as rich text: `open/2`), and `[+:W<key>]`
  around other markup, which is refreshed after a save. `key` is
  `Schema:id:field`.
  """

  alias Brando.Blueprint.Forms
  alias Brando.FrontendEdit
  alias Brando.Villain.TemplateView

  @type kind :: :value | :text | :rich_text | :markup

  # The letter each kind of marker carries (`open/2`)
  @kinds %{value: "E", text: "T", rich_text: "R", markup: "W"}

  @doc "The key a field's markers carry: `Schema:id:field`."
  def key(schema, id, field), do: FrontendEdit.field_key(schema, id, field)

  @doc """
  Resolves a key to `{schema, id, field}` when `field` is an input on the
  schema's admin form, so a key from the page cannot name arbitrary atoms or
  modules.
  """
  @spec parse_key(binary()) :: {:ok, {module(), integer(), atom()}} | :error
  def parse_key(key) when is_binary(key) do
    with [schema_name, id, field_name] <- String.split(key, ":"),
         {id, ""} <- Integer.parse(id),
         {:ok, schema} <- existing_module(schema_name),
         %{} = input <- input_by_name(schema, field_name) do
      {:ok, {schema, id, input.name}}
    else
      _ -> :error
    end
  end

  def parse_key(_), do: :error

  @doc "The input for `field` on the schema's default admin form, or nil."
  def input(schema, field) when is_atom(field), do: input_by_name(schema, to_string(field))
  def input(_schema, _field), do: nil

  defp input_by_name(schema, name) do
    with true <- form?(schema),
         %Forms.Form{} = form <- schema.__form__(:default),
         %Forms.Input{} = input <- Forms.get_field(name, form),
         true <- to_string(input.name) == name do
      input
    else
      _ -> nil
    end
  end

  defp form?(schema) do
    is_atom(schema) and Code.ensure_loaded?(schema) and function_exported?(schema, :__form__, 1) and
      function_exported?(schema, :__admin_route__, 2)
  end

  defp existing_module(name) do
    module = String.to_existing_atom("Elixir." <> name)
    if Code.ensure_loaded?(module), do: {:ok, module}, else: :error
  rescue
    ArgumentError -> :error
  end

  @doc """
  `name` as the field of `entry` it names: an input on the entry's admin
  form, or else an existing key of the entry. Nil for anything else.
  """
  def field(%{__struct__: schema} = entry, name) when is_binary(name) do
    case input_by_name(schema, name) do
      %{name: field} -> field
      nil -> Enum.find(Map.keys(entry), &(is_atom(&1) and to_string(&1) == name))
    end
  end

  def field(_entry, _name), do: nil

  @doc "The field's label, as its admin form shows it."
  def label(schema, field) do
    case input(schema, field) do
      %{opts: opts} when is_list(opts) ->
        case Keyword.get(opts, :label) do
          label when is_binary(label) -> translate(schema, label)
          _ -> humanize(field)
        end

      _ ->
        humanize(field)
    end
  end

  defp translate(schema, msgid) do
    if Brando.Blueprint.blueprint?(schema) do
      domain = String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")
      Gettext.dgettext(schema.__modules__().gettext, domain, msgid)
    else
      msgid
    end
  end

  defp humanize(field), do: field |> to_string() |> Phoenix.Naming.humanize()

  @doc """
  The field's value as HTML, as `{{ }}` prints it: a field it prints as rich
  text (`Brando.Villain.TemplateView.rich_text_fields/2`) sanitized
  (`Brando.Villain.TemplateView.sanitize_rich_text/1`), anything else
  escaped. Media and relations have no value to print; mark the markup that
  shows them with `editable` instead.
  """
  @spec render_value(map(), atom()) :: iodata()
  def render_value(%{__struct__: _} = entry, field),
    do: render_value(entry, field, TemplateView.rich_text_fields(entry, nil))

  def render_value(entry, field) when is_map(entry), do: entry |> Map.get(field) |> to_string_or_empty() |> escape()

  @doc """
  `render_value/2` by the rule `rich`, the fields printed as rich text: for a
  subform row read through its owner, those the owner's forms draw so
  (`Brando.RichText.row_fields_for_printing/2`).
  """
  @spec render_value(map(), atom(), [atom()]) :: iodata()
  def render_value(entry, field, rich) do
    value = Map.get(entry, field)

    cond do
      is_nil(value) -> ""
      is_binary(value) and field in rich -> TemplateView.sanitize_rich_text(value)
      is_binary(value) -> escape(value)
      is_number(value) or is_atom(value) -> value |> to_string() |> escape()
      printable?(value) -> value |> to_string() |> escape()
      true -> ""
    end
  end

  defp printable?(value), do: String.Chars.impl_for(value) && not is_struct(value, Ecto.Association.NotLoaded)

  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(value) when is_binary(value), do: value
  defp to_string_or_empty(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: "")

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc """
  Wraps `html` in markers of `kind` (`open/2`) for `entry`'s `field`, while
  annotating. Otherwise returns `html` untouched.
  """
  @spec wrap(iodata(), map(), atom() | binary(), kind()) :: iodata()
  def wrap(html, entry, field, kind) do
    case marker_key(entry, field) do
      nil -> html
      key -> [open(kind, key), html, close(kind, key)]
    end
  end

  @doc "The key to mark `entry`'s `field` with, or nil when it is not marked now."
  def marker_key(%{__struct__: schema, id: id}, field) when not is_nil(id) and not is_nil(field) do
    field = if is_binary(field), do: field, else: to_string(field)

    if FrontendEdit.annotating?() and input_by_name(schema, field), do: key(schema, id, field)
  end

  def marker_key(_entry, _field), do: nil

  @doc """
  The comment that opens a field marker of `kind`. `:value` wraps the field's
  value as the entry's own forms print it (`render_value/2`); `:text` and
  `:rich_text` wrap it printed as text or as rich text by another rule, a
  subform row's field by its owner's forms (`render_value/3`); `:markup`
  wraps other markup that shows the field. Close it with `close/2`.
  """
  def open(kind, key), do: ["<!-- [+:", Map.fetch!(@kinds, kind), "<", key, ">] -->"]

  @doc "The comment that closes a marker opened with `open/2` for the same kind and key."
  def close(kind, key), do: ["<!-- [-:", Map.fetch!(@kinds, kind), "<", key, ">] -->"]

  @doc """
  What each kind of value marker of `entry`'s `field` that `letters` name
  holds, by the letter its comments carry: as the page prints it there. The
  page names the kinds it has markers of, and puts each in the places marked
  with its kind as the field is edited.
  """
  @spec printed(map(), atom(), String.t()) :: %{String.t() => String.t()}
  def printed(entry, field, letters) do
    for {kind, letter} <- @kinds, kind != :markup, String.contains?(letters, letter), into: %{} do
      {letter, entry |> print(field, kind) |> IO.iodata_to_binary()}
    end
  end

  defp print(entry, field, :value), do: render_value(entry, field)
  defp print(entry, field, :text), do: render_value(entry, field, [])
  defp print(entry, field, :rich_text), do: render_value(entry, field, [field])
end
