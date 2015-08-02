defmodule Brando.Form.Fields do
  @moduledoc """
  Functions for rendering form fields.
  These are all called from the `Brando.Form` module, and handled
  through `Brando.Form.get_form/4`
  """

  import Brando.HTML, only: [media_url: 1, img: 2]

  @doc """
  Renders file field. Wraps the field with a label and row span
  """
  def render_field(form_type, name, :file, opts, value, errors) do
    file(form_type, format_name(name, opts[:source]), value, errors, opts)
    |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render textarea.
  Pass a form_group_class to ensure we don't set height on wrapper.
  """
  def render_field(form_type, name, :textarea, opts, value, errors) do
    textarea(form_type, format_name(name, opts[:source]), value, errors,
             Map.put(opts, :form_group_class, "no-height"))
    |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render group of radio buttons.
  """
  def render_field(form_type, name, :radio, opts, value, errors) do
    render_radios(form_type, format_name(name, opts[:source]), opts, value, errors)
    |> Enum.join("")
    |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render checkboxes. Both groups and singles.
  """
  def render_field(form_type, name, :checkbox, opts, value, errors) do
    if opts[:multiple] do
      render_checks(form_type, format_name(name, opts[:source]), opts, value, errors)
      |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
      |> form_group(format_name(name, opts[:source]), opts, errors)
      |> div_form_row(opts[:in_fieldset])
    else
      concat_fields(label(format_name(name, opts[:source]), opts[:label_class],
                          input(:checkbox, form_type, format_name(name, opts[:source]), value, errors, opts) <>
                          get_label(opts)), label(format_name(name, opts[:source]), "", ""))
      |> div_tag("checkbox")
      |> form_group(format_name(name, opts[:source]), opts, errors)
      |> div_form_row(opts[:in_fieldset])
    end
  end

  @doc """
  Render select. Calls `render_options`
  """
  def render_field(form_type, name, :select, opts, value, errors) do
    choices = render_options(form_type, opts, value, errors)
    select(form_type, format_name(name, opts[:source]), choices, opts, value, errors)
    |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render submit button
  """
  def render_field(form_type, name, :submit, opts, _value, errors) do
    text = case opts[:text] do
      :save -> Brando.Form.t!(opts[:language], "form.save")
      text -> text
    end
    input(:submit, form_type, format_name(name, opts[:source]), text, errors, opts)
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render fieldset open
  """
  def render_field(_, _, :fieldset, opts, _, _) do
    legend =
      case opts[:legend] do
        {:i18n, key} -> opts[:model].t!(opts[:language], key)
        legend -> legend
      end
    fieldset_open_tag(legend, opts[:row_span])
  end

  @doc """
  Render fieldset close
  """
  def render_field(_, _, :fieldset_close, _, _, _), do:
    fieldset_close_tag()

  @doc """
  Render text/password/email (catchall)
  """
  def render_field(form_type, name, input_type, opts, value, errors) do
    confirm_i18n = if opts[:language] == "no", do: "Bekreft", else: "Confirm"
    confirm = if opts[:confirm] do
      confirm_opts =
        opts
        |> Map.put(:label, "#{confirm_i18n} #{get_label(opts)}")
        |> Map.put(:placeholder, "#{confirm_i18n} #{get_label(opts)}")

      input(input_type, form_type, format_name("#{name}_confirmation", opts[:source]), value, errors, confirm_opts)
      |> concat_fields(label(format_name("#{name}_confirmation", opts[:source]), confirm_opts[:label_class], confirm_opts[:label]))
      |> form_group(format_name("#{name}_confirmation", opts[:source]), confirm_opts, errors)
    else
      ""
    end

    field =
      input(input_type, form_type, format_name(name, opts[:source]), value, errors, opts)
      |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
      |> form_group(format_name(name, opts[:source]), opts, errors)

    confirm
    |> concat_fields(field)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Iterates through `opts` :choices key, rendering options for the select
  """
  def render_options(form_type, opts, value, _errors) do
    for choice <- get_choices(opts) do
      option(form_type, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="radio"s
  """
  def render_radios(form_type, name, opts, value, _errors) do
    for choice <- get_choices(opts) do
      radio(form_type, name, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="checkbox"s
  """
  def render_checks(form_type, name, opts, value, _errors) do
    checks = for choice <- get_choices(opts) do
      checkbox(form_type, name, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
    empty_value =
      case opts[:empty_value] do
        nil -> ""
        val -> ~s(<input type="hidden" value="#{val}" name="#{name}" />)
      end
    "#{empty_value}#{Enum.join(checks, "")}"
  end

  @doc """
  Returns a div classed as `form-group` (used in bootstrap).

  Sets classes:

    * `required` -- if the wrapped field is marked such
    * `has-error` -- if the field is found in `errors`
  """
  @spec form_group(String.t, String.t, Keyword.t, Keyword.t) :: String.t
  def form_group(contents, _name, opts, errors) do
    "<div class=\"form-group" <>
    get_form_group_class(opts[:form_group_class]) <>
    get_required(opts[:required]) <>
    get_has_error(errors) <> "\">" <>
    contents <>
    render_errors(errors) <>
    render_help_text(opts) <>
    "</div>"
  end

  @doc """
  Renders `help_text` in a nicely formatted div.
  """
  @spec render_help_text(String.t | nil) :: String.t
  def render_help_text(nil), do: ""
  def render_help_text([]), do: ""
  def render_help_text(%{help_text: help_text}) do
    "<div class=\"help\">" <>
    "<i class=\"fa fa-fw fa-question-circle\"> </i>" <>
    "<span>" <> help_text <> "</span>" <>
    "</div>"
  end
  def render_help_text(%{name: name, model: model, language: language}) do
    case model.t(language, "help.#{name}") do
      {:ok, translation} ->
        "<div class=\"help\">" <>
        "<i class=\"fa fa-fw fa-question-circle\"> </i>" <>
        "<span>" <> translation <> "</span>" <>
        "</div>"
      {:error, _} ->
        ""
    end
  end
  def render_help_text(_) do
    ""
  end

  @doc """
  Renders `errors` in a nicely formatted div by calling parse_error/1
  on each error in the `errors` list.
  """
  @spec render_errors(Options.t | Keyword.t) :: String.t
  def render_errors([]), do: ""
  def render_errors(errors) when is_list(errors) do
    errors = for error <- errors do
      "<div class=\"error\">" <>
      "<i class=\"fa fa-exclamation-circle\"> </i> " <>
      parse_error(error) <> "</div>"
    end
    Enum.join(errors)
  end

  @doc """
  Translate errors
  """
  @spec parse_error(String.t | {String.t, integer}) :: String.t
  def parse_error(error) do
    case error do
      "can't be blank"     -> "Feltet er påkrevet."
      "must be unique"     -> "Feltet må være unikt. Verdien finnes allerede i databasen."
      "has invalid format" -> "Feltet har feil format."
      "is invalid"         -> "Feltet er ugyldig."
      "is reserved"        -> "Verdien er reservert."
      {"should be at least %{count} characters", count: length} -> "Feltets verdi er for kort. Må være > #{length} tegn."
      err                  -> if is_binary(err), do: err, else: inspect(err)
    end
  end

  @doc """
  Concats `wrapped_field` and `label`, with `label` being
  the first
  """
  @spec concat_fields(String.t, String.t) :: String.t
  def concat_fields(wrapped_field, label), do:
    label <> wrapped_field

  @doc """
  Returns a div with class=`class` and `content`
  """
  @spec div_tag(String.t, String.t) :: String.t
  def div_tag(contents, class), do:
    "<div class=\"#{class}\">#{contents}</div>"

  @doc """
  Wraps `field` in a div with `wrapper_class` as class.
  """
  @spec wrap(String.t, String.t | nil) :: String.t
  def wrap(field, nil), do: field
  def wrap(field, wrapper_class), do:
    "<div class=\"#{wrapper_class}\">#{field}</div>"

  @doc """
  Renders a label for `name`, with `class` and `text` as the
  label's content.
  """
  @spec label(String.t, String.t, String.t) :: String.t
  def label(_, _, false), do: ""
  def label(name, class, text), do:
    "<label for=\"#{name}\" class=\"#{class}\">#{text}</label>"

  @doc """
  Render a file field for :update. If we have `value`, try to render
  an img element with a thumbnail.
  """
  @spec file(atom, String.t, String.t, Options.t | Keyword.t, Options.t | Keyword.t) :: String.t
  def file(:update, name, value, _errors, opts) do
    opts = Map.delete(opts, :default)
    get_img_preview(value) <> file(:create, name, value, _errors, opts)
  end

  @doc """
  Render a file field for :create.
  """
  def file(:create, name, _value, _errors, opts) do
    "<input name=\"#{name}\" type=\"file\"#{get_placeholder(opts)}#{get_class(opts[:class])} />"
  end

  @doc """
  Render a textarea field for :update.
  """
  @spec textarea(atom, String.t, String.t, Options.t | Keyword.t, Options.t | Keyword.t) :: String.t
  def textarea(:update, name, value, _errors, opts) do
    opts = Map.delete(opts, :default)
    textarea(:create, name, value, _errors, opts)
  end

  @doc """
  Render a textarea field for :create.
  """
  def textarea(_form_type, name, [], _errors, opts) do
    default = if opts[:default], do: opts[:default], else: ""
    ~s(<textarea name="#{name}"#{get_rows(opts[:rows])}#{get_class(opts[:class])}>#{default}</textarea>)
  end
  def textarea(_form_type, name, value, _errors, opts) when is_map(value) or is_list(value) do
    ~s(<textarea name="#{name}"#{get_rows(opts[:rows])}#{get_class(opts[:class])}>#{Poison.encode!(value)}</textarea>)
  end
  def textarea(_form_type, name, value, _errors, opts) do
    ~s(<textarea name="#{name}"#{get_rows(opts[:rows])}#{get_class(opts[:class])}>#{value}</textarea>)
  end

  @doc """
  Renders a select tag. Passes `choices` to tag/4

  ## Parameters:

    * `name`: name of field
    * `choices`: list of choices to be iterated as options
    * `opts`: list with options for the field
    * `_value`: empty
    * `_errors`: empty
  """
  def select(_, name, choices, opts, _value, _errors) do
    opts = Map.delete(opts, :default)
    case opts[:multiple] do
      nil  -> tag("select", name, choices, opts[:class])
      true -> ~s(<select name="#{name}[]" multiple>#{choices}</select>)
    end
  end

  def option(form_type, choice_value, choice_text, value, default, is_selected_fun \\ nil)
  def option(:update, choice_value, choice_text, value, _default, is_selected_fun) do
    if is_selected_fun do
      selected = case is_selected_fun.(choice_value, value) do
        true  -> " " <> "selected"
        false -> ""
      end
    else
      selected = get_selected(choice_value, value)
    end
    ~s(<option value="#{choice_value}"#{selected}>#{choice_text}</option>)
  end

  # no `value` - :create - match `choice_value` to `default`
  def option(:create, choice_value, choice_text, [], default, _) do
    ~s(<option value="#{choice_value}"#{get_selected(choice_value, default)}>#{choice_text}</option>)
  end

  def option(:create, choice_value, choice_text, value, _default, _) do
    ~s(<option value="#{choice_value}"#{get_selected(choice_value, value)}>#{choice_text}</option>)
  end

  def radio(form_type, name, choice_value, choice_text, value, default, is_selected_fun \\ nil)
  def radio(:create, name, choice_value, choice_text, [], default, _) do
    "<div class=\"radio\">" <>
    "<label for=\"" <> name <> "\"></label>" <>
    "<label for=\"" <> name <> "\">" <>
    "<input name=\"" <> name <> "\" type=\"radio\" " <>
    "value=\"" <> choice_value <>
    "\"" <> get_checked(choice_value, default) <> " />" <>
    choice_text <>
    "</label>" <>
    "</div>"
  end

  def radio(_, name, choice_value, choice_text, value, _default, is_selected_fun) do
    if is_selected_fun do
      checked = case is_selected_fun.(choice_value, value) do
        true  -> " " <> "checked"
        false -> ""
      end
    else
      checked = get_checked(choice_value, value)
    end
    if is_integer(choice_value), do:
      choice_value = Integer.to_string(choice_value)
    "<div class=\"radio\">" <>
    "<label for=\"" <> name <> "\"></label>" <>
    "<label for=\"" <> name <> "\">" <>
    "<input name=\"" <> name <> "\" type=\"radio\" value=\"" <>
    choice_value <> "\"" <> checked <> " />" <>
    choice_text <> "</label>" <> "</div>"
  end

  def checkbox(form_type, name, choice_value, choice_text, value, default, is_selected_fun \\ nil)
  def checkbox(:create, name, choice_value, choice_text, [], default, _) do
    "<div class=\"checkboxes\">" <>
    "<label for=\"" <> name <> "\"></label>" <>
    "<label for=\"" <> name <> "\">" <>
    "<input name=\"" <> name <>
    "[]\" type=\"checkbox\" " <>
    "value=\"" <> choice_value <>
    "\"" <> get_checked(choice_value, default) <> " />" <>
    choice_text <> "</label>" <> "</div>"
  end

  def checkbox(_, name, choice_value, choice_text, value, _default, is_selected_fun) do
    checked = if is_selected_fun do
      case is_selected_fun.(choice_value, value) do
        true  -> " " <> "checked"
        false -> ""
      end
    else
      get_checked(choice_value, value)
    end
    "<div class=\"checkboxes\">" <>
    "<label for=\"" <> name <> "[]\"></label>" <>
    "<label for=\"" <> name <> "[]\">" <>
    "<input name=\"" <> name <> "[]\" type=\"checkbox\" " <>
    "value=\"" <> choice_value <> "\"" <> checked <> " />" <>
    choice_text <> "</label>" <> "</div>"
  end

  def fieldset_open_tag(nil, _in_fieldset), do:
    ~s(<fieldset><div class="form-row">)

  def fieldset_open_tag(legend, _in_fieldset), do:
    ~s(<fieldset><legend><br>#{legend}</legend><div class="form-row">)

  def fieldset_close_tag(), do:
    ~s(</div></fieldset>)

  def div_form_row(content, nil), do:
    ~s(<div class="form-row">#{content}</div>)
  def div_form_row(content, _span), do: content

  def input(:checkbox, _form_type, name, value, _errors, opts) do
    checked =
      case value do
        v when v in ["on", true, "true"]  -> " " <> "checked=\"checked\""
        v when v in [false, nil, "false"] -> ""
        [] ->
          case opts[:default] do
            true  -> " " <> "checked=\"checked\""
            false -> ""
            nil   -> ""
          end
      end
    "<input name=\"" <> name <> "\" type=\"hidden\" value=\"false\">" <>
    "<input name=\"" <> name <> "\" value=\"true\" type=\"checkbox\"" <>
    get_placeholder(opts) <>
    get_class(opts[:class]) <>
    checked <> " />"
  end

  def input(input_type, :update, name, value, _errors, opts) do
    opts = Map.delete(opts, :default)
    input(input_type, :create, name, value, _errors, opts)
  end

  def input(input_type, _form_type, name, value, _errors, opts) do
    "<input name=\"#{name}\" type=\"#{input_type}\"#{get_slug_from(name, opts)}#{get_val(value, opts[:default])}#{get_placeholder(opts)}#{get_class(opts[:class])}#{get_tags_input(opts[:tags])} />"
  end

  def tag(tag, name, contents, class) do
    ~s(<#{tag} name="#{name}" class="#{class}">#{contents}</#{tag}>)
  end

  @doc """
  Matches `cv` to `v`. If true then return "selected" to be used in
  select's options.
  """
  def get_selected(cv, v) when cv == v, do: " " <> "selected"
  def get_selected(cv, v) when is_list(v) do
    if cv in v, do: " " <> "selected"
  end
  def get_selected(_, _), do: ""

  @doc """
  Matches `cv` to `v`. If true then return "checked" to be used in
  input type radio and checkbox
  """
  def get_checked(cv, v) when cv == v, do: " " <> "checked"
  def get_checked(cv, v) when is_list(v) do
    if cv in v, do: " " <> "checked", else: ""
  end
  def get_checked(_, _), do: ""

  @doc """
  If `true`, returns required
  """
  def get_required(true), do: " " <> "required"
  def get_required(nil), do: " " <> "required"
  def get_required(false), do: ""

  @doc """
  If whatever is passed to `get_has_error/1` isn't an empty list,
  it returns "has-error".
  """
  def get_has_error([]), do: ""
  def get_has_error(_), do: " " <> "has-error"

  @doc """
  If `placeholder` is not nil, returns placeholder
  """
  def get_placeholder(nil), do: ""
  def get_placeholder(%{type: :submit}) do
    ""
  end
  def get_placeholder(%{name: name, language: language, model: model}) do
    placeholder = case model.t(language, "model.#{name}") do
      {:ok, translation} -> translation
      {:error, _} -> Atom.to_string(name)
    end
    " " <> "placeholder=\"#{placeholder}\""
  end
  def get_placeholder(%{placeholder: nil}) do
    ""
  end
  def get_placeholder(%{placeholder: placeholder}) do
    " " <> "placeholder=\"#{placeholder}\""
  end
  def get_placeholder(_) do
    ""
  end

  @doc """
  Parse and return `opts` looking for label
  """
  def get_label(%{language: language, label: {:i18n, module, field}}) do
    module.t!(language, "model.#{field}")
  end
  def get_label(%{name: name, language: language, label: {:i18n, module}}) do
    module.t!(language, "model.#{name}")
  end
  def get_label(%{label: label}) do
    label
  end
  def get_label(%{name: name, model: model, language: language}) do
    model.t!(language, "model.#{name}")
  end

  @doc """
  If `class` is not nil, returns class
  """
  def get_class(nil), do: ""
  def get_class(class), do: " " <> "class=\"#{class}\""

  @doc """
  If `rows` is not nil, returns rows
  """
  def get_rows(nil), do: ""
  def get_rows(rows), do: " " <> "rows=\"#{rows}\""

  @doc """
  If `value` is not nil, returns value.
  """
  def get_val([]), do: ""
  def get_val(nil), do: ""
  def get_val(value) when is_list(value), do: ~s( value="#{Enum.join(value, ",")}")
  def get_val(value), do: ~s( value="#{value}")

  @doc """
  If `value` is not nil, returns `value`. Else returns `default`
  """
  def get_val(value, nil), do: get_val(value)
  def get_val([], default) when is_function(default), do: get_val(default.())
  def get_val([], default), do: get_val(default)
  def get_val(value, _), do: get_val(value)


  @doc """
  Return form_group_class as `value`, if present.
  """
  def get_form_group_class(nil), do: ""
  def get_form_group_class(value), do: " " <> value

  @doc """
  Return slug_from option, if exists
  """
  def get_slug_from(name, opts) do
    if opts[:slug_from] do
      caps = Regex.named_captures(~r/(?<form_name>\w*)\[(\w*)\]/, name)
      " " <> "data-slug-from=\"#{caps["form_name"]}[#{opts[:slug_from]}]\""
    else
      ""
    end
  end

  @doc """
  Evals the quoted choices function and returns the result
  """
  def get_choices(%{choices: fun, language: language}) do
    apply(fun, [language])
  end
  def get_choices(_) do
    nil
  end

  defp get_tags_input(true), do: " data-tags-input=\"true\""
  defp get_tags_input(nil), do: ""

  defp get_img_preview(nil), do: ""
  defp get_img_preview(value) do
    "<div class=\"image-preview\">" <>
    "<img src=\"" <> media_url(img(value, :thumb)) <> "\" />" <>
    "</div>"
  end

  defp format_name(name, form_source) do
    "#{form_source}[#{name}]"
  end
end