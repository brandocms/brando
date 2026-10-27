defmodule BrandoAdmin.Components.Form.Input.Options do
  @moduledoc """
  Shared expansion of the symbolic `:options` tokens a form input can declare.

  `input :language, :select, options: :languages` is resolved at render time,
  because the language lists come from config and Brando supports changing them
  at runtime (`Brando.RuntimeConfig`) — so this deliberately does NOT memoize.

  Select and MultiSelect cache prepared options against the expanded specification.
  Callable providers are loaded on mount, opening the picker, and explicit refresh.
  Declare `options_depends_on: [:language, ...]` for providers that also need to
  reload when particular form fields change. Other keystrokes do not query them.
  """

  use BrandoAdmin.Translator

  @tokens [:languages, :admin_languages]

  @doc "The `:options` tokens this module expands."
  def tokens, do: @tokens

  @doc """
  Expand `:languages` / `:admin_languages` into `%{label:, value:}` maps.

  Both config keys hold `[[value: "en", text: "English"], …]`.
  """
  def expand(token) when token in @tokens do
    token
    |> Brando.config()
    |> Enum.map(fn [{:value, value}, {:text, text}] -> %{label: text, value: value} end)
  end

  def expand(other), do: other

  @doc """
  Translate the labels of options declared in the Blueprint, like
  `%{value: :published, label: t("Published")}`, in the schema's gettext
  domain, as radios do. Options from a function are data (entry titles and
  the like) and are left alone, and so are a var's: its labels are text an
  admin typed, not msgids.
  """
  def translate_labels(options, %{form: %{source: %{data: %Brando.Content.Var{}}}}), do: options

  def translate_labels(options, %{form: %{source: %{data: %{__struct__: schema}}}}) when is_list(options) do
    Enum.map(options, fn
      %{label: label} = opt when is_binary(label) -> %{opt | label: schema |> g(label) |> Phoenix.HTML.safe_to_string()}
      opt -> opt
    end)
  end

  def translate_labels(options, _field), do: options

  @doc """
  An option label as HTML. Labels are text: entry titles, user names and
  module params come from data other admins control, so a binary label is
  escaped. Option lists written in code that need markup (swatches, icons)
  pass the label as `{:safe, iodata}` (`Phoenix.HTML.raw/1`), which is the
  only way markup reaches the page; stored data never arrives as a tuple.
  """
  def label_html({:safe, _} = label), do: Phoenix.HTML.safe_to_string(label)
  def label_html(nil), do: ""
  def label_html(label), do: label |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc """
  An option label as plain text, for attributes and filtering: the text of a
  `{:safe, iodata}` label without its tags, its entities decoded.
  """
  def label_text({:safe, _} = label),
    do: label |> Phoenix.HTML.safe_to_string() |> HtmlSanitizeEx.strip_tags() |> HtmlEntities.decode()

  def label_text(nil), do: ""
  def label_text(label), do: to_string(label)

  @doc false
  def assign_options(socket, load, force? \\ false) do
    %{field: field, opts: opts} = socket.assigns
    expanded_opts = Keyword.update(opts, :options, nil, &expand/1)
    dependencies = Enum.map(Keyword.get(opts, :options_depends_on, []), &{&1, field.form[&1].value})
    key = {field.form.id, field.field, expanded_opts, dependencies}

    if !force? and socket.assigns[:input_options_key] == key do
      socket
    else
      socket
      |> Phoenix.Component.assign(:input_options, load.(field, expanded_opts))
      |> Phoenix.Component.assign(:input_options_key, key)
    end
  end
end
