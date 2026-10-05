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
  around a printed value, which the page updates as the field is edited,
  and `[+:W<key>]` around other markup, which is refreshed after a save.
  `key` is `Schema:id:field`.
  """

  alias Brando.Blueprint.Forms
  alias Brando.FrontendEdit

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
  The field's value as HTML: rich text as it is stored, anything else
  escaped. Media and relations have no value to print; mark the markup that
  shows them with `editable` instead.
  """
  @spec render_value(map(), atom()) :: iodata()
  def render_value(%{__struct__: schema} = entry, field) do
    value = Map.get(entry, field)

    cond do
      is_nil(value) -> ""
      rich_text?(schema, field) and is_binary(value) -> value
      is_binary(value) -> Phoenix.HTML.html_escape(value) |> Phoenix.HTML.safe_to_string()
      is_number(value) or is_atom(value) -> value |> to_string() |> escape()
      printable?(value) -> value |> to_string() |> escape()
      true -> ""
    end
  end

  def render_value(entry, field) when is_map(entry), do: entry |> Map.get(field) |> to_string_or_empty() |> escape()

  defp printable?(value), do: String.Chars.impl_for(value) && not is_struct(value, Ecto.Association.NotLoaded)

  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(value) when is_binary(value), do: value
  defp to_string_or_empty(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: "")

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc "Whether the field is edited as rich text."
  def rich_text?(schema, field) do
    match?(%Forms.Input{type: :rich_text}, input(schema, field))
  end

  @doc """
  Wraps `html` in value markers (`:value`) or markup markers (`:markup`) for
  `entry`'s `field`, while annotating. Otherwise returns `html` untouched.
  """
  @spec wrap(iodata(), map(), atom() | binary(), :value | :markup) :: iodata()
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
  The comment that opens a field marker: `:value` wraps the field's own rendered
  value, `:markup` wraps other markup that shows it. Close it with `close/2`.
  """
  def open(:value, key), do: ["<!-- [+:E<", key, ">] -->"]
  def open(:markup, key), do: ["<!-- [+:W<", key, ">] -->"]

  @doc "The comment that closes a marker opened with `open/2` for the same kind and key."
  def close(:value, key), do: ["<!-- [-:E<", key, ">] -->"]
  def close(:markup, key), do: ["<!-- [-:W<", key, ">] -->"]
end
