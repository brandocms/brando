defmodule Brando.Form.Fields do
  @moduledoc """
  Functions for rendering form fields.
  These are all called from the `Brando.Form` module, and handled
  through `Brando.Form.get_form/4`
  """
  import Brando.Gettext
  import Brando.Utils, only: [media_url: 0, img_url: 3]
  import Phoenix.HTML.Tag, only: [content_tag: 3, content_tag: 2, tag: 2]
  import Phoenix.HTML, only: [raw: 1]

  @doc """
  Renders file field. Wraps the field with a label and row span
  """
  def render_field(form_type, %{name: name, type: :file} = opts, value, errors) do
    i = file(form_type, format_name(name, opts[:source]), value, errors, opts)
    i
    |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render textarea.
  Pass a form_group_class to ensure we don't set height on wrapper.
  """
  def render_field(form_type, %{name: name, type: :textarea} = opts, value, errors) do
    i = textarea(form_type, format_name(name, opts[:source]), value, errors,
                 Map.put(opts, :form_group_class, "no-height"))
    i
    |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render group of radio buttons.
  """
  def render_field(form_type, %{name: name, type: :radio} = opts, value, errors) do
    i = render_radios(form_type, format_name(name, opts[:source]), opts, value, errors)
    i
    |> concat_fields(label(format_name(name, opts[:source]), opts[:label_class], get_label(opts)))
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render checkbox group.
  """
  def render_field(form_type, %{name: name, type: :checkbox, multiple: _} = opts, value, errors) do
    i = render_checks(form_type, format_name(name, opts[:source]),
                      opts, value, errors)
    l =
      name
      |> format_name(opts[:source])
      |> label(opts[:label_class], get_label(opts))

    i
    |> concat_fields(l)
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render checkbox single
  """
  def render_field(form_type, %{name: name, type: :checkbox} = opts, value, errors) do
    label_content =
      [input(:checkbox, form_type, format_name(name, opts[:source]),
             value, errors, opts), get_label(opts)]
    name
    |> format_name(opts[:source])
    |> label(opts[:label_class], label_content)
    |> concat_fields(label(format_name(name, opts[:source]), "", ""))
    |> div_tag("checkbox")
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render select. Calls `render_options`
  """
  def render_field(form_type, %{name: name, type: :select} = opts, value, errors) do
    choices = render_options(form_type, opts, value, errors)
    i = select(form_type, format_name(name, opts[:source]),
               choices, opts, value, errors)
    l =
      name
      |> format_name(opts[:source])
      |> label(opts[:label_class], get_label(opts))

    i
    |> concat_fields(l)
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render submit button
  """
  def render_field(form_type, %{name: name, type: :submit} = opts, _value, errors) do
    text = case opts[:text] do
      :save -> gettext("Save")
      text -> text
    end
    i = input(:submit, form_type, format_name(name, opts[:source]),
              text, errors, opts)
    i
    |> form_group(format_name(name, opts[:source]), opts, errors)
    |> div_form_row(opts[:in_fieldset])
  end

  @doc """
  Render fieldset open
  """
  def render_field(_, %{type: :fieldset} = opts, _, _) do
    fieldset_open_tag(opts[:legend], opts[:row_span])
  end

  @doc """
  Render fieldset close
  """
  def render_field(_, %{type: :fieldset_close}, _, _), do:
    fieldset_close_tag()

  @doc """
  Render text/password/email (catchall)
  """
  def render_field(form_type, %{name: name, type: input_type} = opts, value, errors) do
    confirm_i18n = gettext("Confirm")
    confirm = if opts[:confirm] do
      confirm_opts =
        opts
        |> Map.put(:label, "#{confirm_i18n} #{get_label(opts)}")
        |> Map.put(:placeholder, "#{confirm_i18n} #{get_label(opts)}")
      conf_name = format_name("#{name}_confirmation", opts[:source])

      l =
        conf_name
        |> label(confirm_opts[:label_class], confirm_opts[:label])

      i = input(input_type, form_type, conf_name, value, errors, confirm_opts)

      i
      |> concat_fields(l)
      |> form_group(conf_name, confirm_opts, errors)
    else
      ""
    end

    i = input(input_type, form_type, format_name(name, opts[:source]),
              value, errors, opts)
    l =
      name
      |> format_name(opts[:source])
      |> label(opts[:label_class], get_label(opts))

    field =
      i
      |> concat_fields(l)
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
      option(form_type, choice[:value], choice[:text],
             value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="radio"s
  """
  def render_radios(form_type, name, opts, value, _errors) do
    for choice <- get_choices(opts) do
      radio(form_type, name, choice[:value], choice[:text],
            value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="checkbox"s
  """
  def render_checks(form_type, name, opts, value, _errors) do
    checks = for choice <- get_choices(opts) do
      checkbox(form_type, name, choice[:value], choice[:text],
               value, opts[:default], opts[:is_selected])
    end
    empty_value =
      case opts[:empty_value] do
        nil -> ""
        val ->
          {:safe, html} = tag(:input, [type: :hidden, value: val, name: name])
          html
      end
    [empty_value, checks]
  end

  @doc """
  Returns a div classed as `form-group` (used in bootstrap).

  Sets classes:

    * `required` -- if the wrapped field is marked such
    * `has-error` -- if the field is found in `errors`
  """
  @spec form_group(String.t, String.t, Keyword.t, Keyword.t) :: String.t
  def form_group(contents, _name, opts, errors) do
    classes = [class: get_group_classes(opts, errors)]
    {:safe, html} = content_tag(:div, classes) do
      [contents, render_errors(errors, opts), render_help_text(opts)] |> raw
    end
    html
  end

  @doc """
  Renders `help_text` in a nicely formatted div.
  """
  @spec render_help_text(String.t | nil) :: String.t
  def render_help_text(nil), do: ""
  def render_help_text([]), do: ""
  def render_help_text(%{help_text: help_text}) do
    {:safe, html} = content_tag(:div, class: "help") do
      [content_tag(:i, " ", class: "fa fa-fw fa-question-circle"),
       content_tag(:span, help_text)]
    end
    html
  end

  def render_help_text(_) do
    ""
  end

  @doc """
  Renders `errors` in a nicely formatted div by calling parse_error/1
  on each error in the `errors` list.
  """
  @spec render_errors(Options.t | Keyword.t, Keyword.t) :: String.t
  def render_errors(nil, _opts), do: ""
  def render_errors(errors, opts) when is_list(errors) do
    for error <- errors do
      {:safe, html} = content_tag(:div, class: "error") do
        [content_tag(:i, " ", class: "fa fa-exclamation-circle"),
         parse_error(error, opts)]
      end
      html
    end
  end

  @doc """
  Translate errors
  """
  @spec parse_error(String.t | {String.t, integer}, Keyword.t) :: String.t
  def parse_error(error, _) do
    case error do
      "can't be blank"     ->
        gettext("can't be blank")
      "must be unique"     ->
        gettext("must be unique")
      "has invalid format" ->
        gettext("has invalid format")
      "is invalid"         ->
        gettext("is invalid")
      "is reserved"        ->
        gettext("is reserved")
      {"should be at least %{count} characters", count: length} ->
        gettext("should be at least %{count} characters", count: length)
      err                  ->
        is_binary(err) && err || inspect(err)
    end
  end

  @doc """
  Concats `wrapped_field` and `label`, with `label` being
  the first
  """
  @spec concat_fields(String.t, String.t) :: String.t
  def concat_fields(wrapped_field, label), do:
    [label, wrapped_field]

  @doc """
  Returns a div with class=`class` and `content`
  """
  @spec div_tag(String.t, String.t) :: String.t
  def div_tag(content, class) do
    {:safe, html} = content_tag(:div, class: class) do
      content |> raw
    end
    html
  end

  @doc """
  Wraps `field` in a div with `wrapper_class` as class.
  """
  @spec wrap(String.t, String.t | nil) :: String.t
  def wrap(field, nil), do: field
  def wrap(field, class) do
    {:safe, html} = content_tag(:div, class: class) do
      field |> raw
    end
    html
  end

  @doc """
  Renders a label for `name`, with `class` and `text` as the
  label's content.
  """
  @spec label(String.t, String.t, String.t) :: String.t
  def label(_, _, false), do: ""
  def label(name, class, text) do
    {:safe, html} = content_tag(:label, for: name, class: class) do
      text |> raw
    end
    html
  end

  @doc """
  Render a file field for :update. If we have `value`, try to render
  an img element with a thumbnail.
  """
  @spec file(atom, String.t, String.t, Options.t | Keyword.t,
             Options.t | Keyword.t) :: String.t
  def file(:update, name, value, errors, opts) do
    opts = Map.delete(opts, :default)
    [get_img_preview(value), file(:create, name, value, errors, opts)]
  end

  @doc """
  Render a file field for :create.
  """
  def file(:create, name, _value, _errors, opts) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(:file)
      |> put_class(opts)
      |> put_placeholder(opts)

    {:safe, html} = tag(:input, tag_opts)
    html
  end

  @doc """
  Render a textarea field for :update.
  """
  @spec textarea(atom, String.t, String.t, Options.t | Keyword.t,
                 Options.t | Keyword.t) :: String.t
  def textarea(:update, name, value, errors, opts) do
    opts = Map.delete(opts, :default)
    textarea(:create, name, value, errors, opts)
  end

  @doc """
  Render a textarea field for :create.
  """
  def textarea(_form_type, name, nil, _errors, opts) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_class(opts)
      |> put_rows(opts)

    {:safe, html} = content_tag(:textarea, tag_opts) do
      opts[:default] || ""
    end
    html
  end
  def textarea(_form_type, name, value, _errors, opts)
      when is_map(value) or is_list(value) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_rows(opts)
      |> put_class(opts)

    {:safe, html} = content_tag(:textarea, tag_opts) do
      Poison.encode!(value)
    end
    html
  end
  def textarea(_form_type, name, value, _errors, opts) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_rows(opts)
      |> put_class(opts)

    {:safe, html} = content_tag(:textarea, tag_opts) do
      value || ""
    end
    html
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
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_class(opts)

    case opts[:multiple] do
      nil  ->
        {:safe, html} = content_tag(:select, tag_opts) do
          choices |> raw
        end
        html
      true ->
        {:safe, html} = content_tag(:select, [name: "#{name}[]", multiple: true]) do
          choices |> raw
        end
        html
    end
  end

  def option(form_type, choice_value, choice_text, value, default,
             is_selected_fun \\ nil)
  def option(:update, choice_value, choice_text, value, _default, nil) do
    tag_opts =
      Keyword.new
      |> put_value(choice_value)
      |> put_selected(get_selected(choice_value, value))

    {:safe, html} = content_tag(:option, tag_opts) do
      choice_text |> raw
    end
    html
  end

  def option(:update, choice_value, choice_text, value, _default, is_selected_fun) do
    tag_opts =
      Keyword.new
      |> put_value(choice_value)
      |> put_is_selected_fun(is_selected_fun, choice_value, value)

    {:safe, html} = content_tag(:option, tag_opts) do
      choice_text |> raw
    end
    html
  end

  # no `value` - :create - match `choice_value` to `default`
  def option(:create, choice_value, choice_text, nil, default, _) do
    tag_opts =
      Keyword.new
      |> put_value(choice_value)
      |> put_selected(get_selected(choice_value, default))

    {:safe, html} = content_tag(:option, tag_opts) do
      choice_text |> raw
    end
    html
  end

  def option(:create, choice_value, choice_text, value, _default, _) do
    tag_opts =
      Keyword.new
      |> put_value(choice_value)
      |> put_selected(get_selected(choice_value, value))

    {:safe, html} = content_tag(:option, tag_opts) do
      choice_text |> raw
    end
    html
  end

  def radio(form_type, name, choice_value, choice_text, value, default, is_checked_fun \\ nil)
  def radio(:create, name, choice_value, choice_text, nil, default, _) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(:radio)
      |> put_value(choice_value)
      |> put_checked_match(get_checked(choice_value, default))

    {:safe, input_html} = tag(:input, tag_opts)

    {:safe, dummy_label_html} = content_tag(:label, for: name) do
      ""
    end

    {:safe, main_label_html} = content_tag(:label, for: name) do
      [input_html, choice_text] |> raw
    end

    {:safe, wrap_html} = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end

    wrap_html
  end

  def radio(_, name, choice_value, choice_text, value, _default, nil) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(:radio)
      |> put_value(choice_value)
      |> put_checked_match(get_checked(choice_value, value))

    {:safe, input_html} = tag(:input, tag_opts)

    {:safe, dummy_label_html} = content_tag(:label, for: name) do
      ""
    end

    {:safe, main_label_html} = content_tag(:label, for: name) do
      [input_html, choice_text] |> raw
    end

    {:safe, wrap_html} = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end

    wrap_html
  end

  def radio(_, name, choice_value, choice_text, value, _default, is_checked_fun) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(:radio)
      |> put_value(choice_value)
      |> put_is_checked_fun(is_checked_fun, choice_value, value)

    {:safe, input_html} = tag(:input, tag_opts)

    {:safe, dummy_label_html} = content_tag(:label, for: name) do
      ""
    end

    {:safe, main_label_html} = content_tag(:label, for: name) do
      [input_html, choice_text] |> raw
    end

    {:safe, wrap_html} = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end

    wrap_html
  end

  @doc """
  Renders a checkbox.

  This is for multiple checkboxes. Single checks are
  handled through `input(:checkbox, ...)`
  """
  def checkbox(form_type, name, choice_value, choice_text,
               value, default, is_checked_fun \\ nil)
  def checkbox(:create, name, choice_value, choice_text, nil, default, _) do
    tag_opts =
      Keyword.new
      |> put_name("#{name}[]")
      |> put_type(:checkbox)
      |> put_value(choice_value)
      |> put_checked_match(get_checked(choice_value, default))

    {:safe, input_html} = tag(:input, tag_opts)

    {:safe, dummy_label_html} = content_tag(:label, for: name) do
      ""
    end

    {:safe, main_label_html} = content_tag(:label, for: name) do
      [input_html, choice_text] |> raw
    end

    {:safe, wrap_html} = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end

    wrap_html
  end

  def checkbox(_, name, choice_value, choice_text, value, _, nil) do
    tag_opts =
      Keyword.new
      |> put_name("#{name}[]")
      |> put_type(:checkbox)
      |> put_value(choice_value)
      |> put_checked_match(get_checked(choice_value, value))

    {:safe, input_html} = tag(:input, tag_opts)

    {:safe, dummy_label_html} = content_tag(:label, for: name) do
      ""
    end

    {:safe, main_label_html} = content_tag(:label, for: name) do
      [input_html, choice_text] |> raw
    end

    {:safe, wrap_html} = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end

    wrap_html
  end

  def checkbox(_, name, choice_value, choice_text, value, _, is_checked_fun) do
    tag_opts =
      Keyword.new
      |> put_name("#{name}[]")
      |> put_type(:checkbox)
      |> put_value(choice_value)
      |> put_is_checked_fun(is_checked_fun, choice_value, value)

    {:safe, input_html} = tag(:input, tag_opts)

    {:safe, dummy_label_html} = content_tag(:label, for: name) do
      ""
    end

    {:safe, main_label_html} = content_tag(:label, for: name) do
      [input_html, choice_text] |> raw
    end

    {:safe, wrap_html} = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end

    wrap_html
  end

  def fieldset_open_tag(nil, _in_fieldset), do:
    ~s(<fieldset><div class="form-row">)

  def fieldset_open_tag(legend, _in_fieldset), do:
    ~s(<fieldset><legend><br>#{legend}</legend><div class="form-row">)

  def fieldset_close_tag(), do:
    ~s(</div></fieldset>)

  def div_form_row(content, nil) do
    {:safe, html} = content_tag(:div, class: "form-row") do
      content |> raw
    end
    html
  end

  def div_form_row(content, _span), do: content

  def input(:checkbox, _form_type, name, value, _errors, opts) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_value("true")
      |> put_type(:checkbox)
      |> put_placeholder(opts)
      |> put_class(opts)
      |> put_checked(value, opts)

    {:safe, hidden_tag} = tag(:input, [name: name, type: :hidden,
                                       value: "false"])
    {:safe, input_tag}  = tag(:input, tag_opts)

    [hidden_tag, input_tag]
  end

  def input(input_type, :update, name, value, errors, opts) do
    opts = Map.delete(opts, :default)
    input(input_type, :create, name, value, errors, opts)
  end

  def input(input_type, _form_type, name, value, _errors, opts) do
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(input_type)
      |> put_value(value, opts)
      |> put_slug_from(name, opts)
      |> put_placeholder(opts)
      |> put_class(opts)
      |> put_tags(opts)

    {:safe, html} = tag(:input, tag_opts)
    html
  end

  defp put_slug_from(tag_opts, name, opts) do
    case opts[:slug_from] do
      nil -> tag_opts
      slug_from ->
         caps = Regex.named_captures(~r/(?<form_name>\w*)\[(\w*)\]/, name)
         Keyword.put(tag_opts, :data_slug_from,
                     "#{caps["form_name"]}[#{slug_from}]")
    end
  end

  defp put_placeholder(tag_opts, opts) do
    case get_placeholder(opts) do
      nil -> tag_opts
      placeholder -> Keyword.put(tag_opts, :placeholder, placeholder)
    end
  end

  defp put_class(tag_opts, []) do
    tag_opts
  end
  defp put_class(tag_opts, opts) do
    case Map.get(opts, :class) do
      nil -> tag_opts
      class -> Keyword.put(tag_opts, :class, class)
    end
  end

  defp put_tags(tag_opts, opts) do
    case Map.get(opts, :tags) do
      nil -> tag_opts
      true -> Keyword.put(tag_opts, :data_tags_input, "true")
    end
  end

  defp put_name(tag_opts, name) do
    Keyword.put(tag_opts, :name, name)
  end

  defp put_value(tag_opts, value, opts) do
    value = get_val(value, opts[:default])
    Keyword.put(tag_opts, :value, value)
  end

  defp put_value(tag_opts, value) do
    Keyword.put(tag_opts, :value, value)
  end

  defp put_type(tag_opts, type) do
    Keyword.put(tag_opts, :type, type)
  end

  defp put_rows(tag_opts, opts) do
    case Map.get(opts, :rows) do
      nil -> tag_opts
      rows -> Keyword.put(tag_opts, :rows, rows)
    end
  end

  defp put_selected(tag_opts, selected) do
    case selected do
      true -> Keyword.put(tag_opts, :selected, true)
      nil  -> tag_opts
    end
  end

  defp put_is_selected_fun(tag_opts, is_selected_fun, choice_value, value) do
    case is_selected_fun.(choice_value, value) do
      true  -> Keyword.put(tag_opts, :selected, true)
      false -> tag_opts
    end
  end

  defp put_is_checked_fun(tag_opts, is_checked_fun, choice_value, value) do
    case is_checked_fun.(choice_value, value) do
      true  -> Keyword.put(tag_opts, :checked, true)
      false -> tag_opts
    end
  end

  defp put_checked(tag_opts, value, opts) do
    case checked?(value, opts) do
      false -> tag_opts
      true -> Keyword.put(tag_opts, :checked, "checked")
    end
  end

  defp put_checked_match(tag_opts, match) do
    case match do
      true -> Keyword.put(tag_opts, :checked, true)
      nil  -> tag_opts
    end
  end

  @doc """
  Matches `cv` to `v`. If true then return "selected" to be used in
  select's options.
  """
  def get_selected(cv, v) when cv == v, do: true
  def get_selected(cv, v) when is_list(v) do
    if cv in v, do: true
  end
  def get_selected(_, _), do: nil

  @doc """
  Matches `cv` to `v`. If true then return true to be used in
  input type radio and checkbox
  """
  def get_checked(cv, v) when cv == v, do: true
  def get_checked(cv, v) when is_list(v) do
    if cv in v, do: true
  end
  def get_checked(_, _), do: nil

  @doc """
  If `placeholder` is not nil, returns placeholder
  """
  def get_placeholder(nil), do: ""
  def get_placeholder(%{type: :submit}) do
    nil
  end
  def get_placeholder(%{type: :file}) do
    nil
  end
  def get_placeholder(%{name: name, model: model}) do
    model.__field__(name)
  end
  def get_placeholder(%{placeholder: nil}) do
    nil
  end
  def get_placeholder(%{placeholder: placeholder}) do
    placeholder
  end
  def get_placeholder(_) do
    nil
  end

  @doc """
  Parse and return `opts` looking for label
  """
  def get_label(%{label: label}) do
    label
  end
  def get_label(%{name: name, model: model}) do
    model.__field__(name)
  end

  @doc """
  If `value` is not nil, returns value.
  """
  def get_val(nil), do: ""
  def get_val(value) when is_list(value), do: Enum.join(value, ",")
  def get_val(value), do: value

  @doc """
  If `value` is not nil, returns `value`. Else returns `default`
  """
  def get_val(value, nil), do: get_val(value)
  def get_val(nil, default) when is_function(default), do: get_val(default.())
  def get_val(nil, default), do: get_val(default)
  def get_val(value, _), do: get_val(value)

  defp checked?(value, opts) do
    case value do
      v when v in ["on", true, "true"]  -> true
      v when v in [false, nil, "false"] -> false
      [] ->
        case opts[:default] do
          true  -> true
          _ -> false
        end
    end
  end

  defp get_group_classes(%{form_group_class: class, required: false}, nil) do
    "form-group #{class}"
  end
  defp get_group_classes(%{form_group_class: class, required: false}, _) do
    "form-group #{class} has-error"
  end
  defp get_group_classes(%{form_group_class: class, required: true}, nil) do
    "form-group #{class} required has-error"
  end
  defp get_group_classes(%{form_group_class: class, required: true}, _) do
    "form-group #{class} required has-error"
  end
  defp get_group_classes(%{form_group_class: class}, nil) do
    "form-group required #{class}"
  end
  defp get_group_classes(%{form_group_class: class}, _) do
    "form-group required #{class} has-error"
  end
  defp get_group_classes(%{required: false}, nil) do
    "form-group"
  end
  defp get_group_classes(%{required: false}, _) do
    "form-group has-error"
  end
  defp get_group_classes(_, nil) do
    "form-group required"
  end
  defp get_group_classes(_, _) do
    "form-group required has-error"
  end

  @doc """
  Evals the quoted choices function and returns the result
  """
  def get_choices(%{choices: fun}) do
    apply(fun, [])
  end
  def get_choices(_) do
    nil
  end

  defp get_img_preview(nil), do: ""
  defp get_img_preview(value) do
    {:safe, html} = content_tag(:div, class: "image-preview") do
      raw(tag(:img, [src: img_url(value, :thumb, prefix: media_url())]))
    end
    html
  end

  defp format_name(name, form_source) do
    "#{form_source}[#{name}]"
  end
end
