defmodule Brando.Form.Fields do
  @moduledoc """
  Functions for rendering form fields.
  These are all called from the `Brando.Form` module, and handled
  through `Brando.Form.get_form/4`
  """
  import Brando.Form.Fields.Utils
  import Brando.Gettext
  import Brando.Utils, only: [media_url: 0, img_url: 3]
  import Phoenix.HTML.Tag, only: [content_tag: 3, content_tag: 2, tag: 2]
  import Phoenix.HTML, only: [raw: 1, safe_to_string: 1]

  alias Brando.Form.Field

  @doc """
  Renders file field. Wraps the field with a label and row span
  """
  @spec render_field(Field.t) :: Field.t
  def render_field(%Field{type: :file} = field) do
    field
    |> file
    |> add_label
    |> wrap_in_form_group
    |> wrap_in_div
  end

  @doc """
  Render textarea.
  Pass a form_group_class to ensure we don't set height on wrapper.
  """
  def render_field(%Field{type: :textarea} = field) do
    field
    |> put_in_opts(:form_group_class, "no-height")
    |> textarea
    |> add_label
    |> wrap_in_form_group
    |> wrap_in_div
  end

  @doc """
  Render group of radio buttons.
  """
  def render_field(%Field{type: :radio} = field) do
    field
    |> radios
    |> add_label
    |> wrap_in_form_group
    |> wrap_in_div
  end

  @doc """
  Render checkbox group.
  """
  def render_field(%Field{type: :checkbox, opts: %{multiple: _}} = field) do
    field
    |> checkboxes
    |> add_label
    |> wrap_in_form_group
    |> wrap_in_div
  end

  @doc """
  Render checkbox single
  """
  def render_field(%Field{type: :checkbox} = field) do
    field
    |> put_in_opts(:multiple, false)
    |> input
    |> add_label
    |> wrap_in_form_group
    |> wrap_in_div
  end

  @doc """
  Render select. Calls `options`
  """
  def render_field(%Field{type: :select} = field) do
    field
    |> options
    |> select
    |> add_label
    |> wrap_in_form_group
    |> wrap_in_div
  end

  @doc """
  Render submit button
  """
  def render_field(%Field{type: :submit} = field) do
    text = if field.opts[:text] == :save do
      gettext("Save")
    else
      field.opts[:text]
    end

    field
    |> put_in_field(:value, text)
    |> input
    |> wrap_in_form_group
    |> wrap_in_div
  end

  @doc """
  Render fieldset open
  """
  def render_field(%Field{type: :fieldset} = field) do
    legend = field.schema.__fieldset__(field.opts[:legend]) || nil
    prepend_html(field, fieldset_open_tag(legend, field.opts[:row_span]))
  end

  @doc """
  Render fieldset close
  """
  def render_field(%Field{type: :fieldset_close} = field) do
    append_html(field, fieldset_close_tag())
  end

  @doc """
  Render datetime field
  """
  def render_field(%Field{type: :datetime} = field) do
    field
    |> put_in_opts(:class, "datetimepicker")
    |> input
    |> add_label
    |> wrap_in_form_group
    |> add_confirm
    |> wrap_in_div
  end

  @doc """
  Render text/password/email (catch-all)
  """
  def render_field(field) do
    field
    |> input
    |> add_label
    |> wrap_in_form_group
    |> add_confirm
    |> wrap_in_div
  end

  @doc """
  Render a file field for :update. If we have `value`, try to render
  an img element with a thumbnail.
  """
  def file(%Field{form_type: :update} = field) do
    field =
      field
      |> delete_in_field(:default)
      |> put_in_field(:form_type, :create)

    prepend_html(field, [get_img_preview(field.value), file(field).html])
  end

  @doc """
  Render a file field for :create.
  """
  def file(%Field{form_type: :create} = field) do
    tag_opts =
      Keyword.new
      |> put_name(format_name(field.name, field.source))
      |> put_type(field.type)
      |> put_class(field.opts)
      |> put_placeholder(field)

    {:safe, html} = tag(:input, tag_opts)
    prepend_html(field, html)
  end

  @doc """
  Render a textarea field for :update.
  """
  @spec textarea(Field.t) :: Field.t
  def textarea(%Field{form_type: :update} = field) do
    field
    |> delete_in_opts(:default)
    |> put_in_field(:form_type, :create)
    |> textarea
  end

  @doc """
  Render a textarea field for :create.
  """
  def textarea(%Field{value: nil} = field) do
    tag_opts =
      Keyword.new
      |> put_name(format_name(field.name, field.source))
      |> put_class(field.opts)
      |> put_rows(field.opts)

    html = content_tag(:textarea, tag_opts) do
      get_val(nil, field.opts[:default] || [])
    end |> safe_to_string

    prepend_html(field, html)
  end

  def textarea(%Field{value: value} = field)
      when is_map(value) or is_list(value) do
    tag_opts =
      Keyword.new
      |> put_name(format_name(field.name, field.source))
      |> put_class(field.opts)
      |> put_rows(field.opts)

    html = content_tag(:textarea, tag_opts) do
      Poison.encode!(value)
    end |> safe_to_string

    prepend_html(field, html)
  end

  def textarea(%Field{value: value} = field) do
    tag_opts =
      Keyword.new
      |> put_name(format_name(field.name, field.source))
      |> put_class(field.opts)
      |> put_rows(field.opts)

    html = content_tag(:textarea, tag_opts) do
      value || ""
    end |> safe_to_string

    prepend_html(field, html)
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="radio"s
  """
  def radios(field) do
    Enum.reduce(get_choices(field), field, fn(choice, acc) ->
      radio(acc, choice)
    end)
  end

  def radio(%Field{form_type: :create, value: nil} = field, choice) do
    name = format_name(field.name, field.source)

    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(:radio)
      |> put_value(choice[:value])
      |> put_checked_match(get_checked(choice[:value], field.opts[:default]))

    input_html = tag(:input, tag_opts) |> safe_to_string

    dummy_label_html = content_tag(:label, for: name) do
      ""
    end |> safe_to_string

    main_label_html = content_tag(:label, for: name) do
      [input_html, choice[:text]] |> raw
    end |> safe_to_string

    wrap_html = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end |> safe_to_string

    append_html(field, wrap_html)
  end

  def radio(%Field{opts: %{is_selected: is_checked_fun}} = field, choice) do
    name = format_name(field.name, field.source)

    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(:radio)
      |> put_value(choice[:value])
      |> put_is_checked_fun(is_checked_fun, choice[:value], field.value)

    input_html = tag(:input, tag_opts) |> safe_to_string

    dummy_label_html = content_tag(:label, for: name) do
      ""
    end |> safe_to_string

    main_label_html = content_tag(:label, for: name) do
      [input_html, choice[:text]] |> raw
    end |> safe_to_string

    wrap_html = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end |> safe_to_string

    append_html(field, wrap_html)
  end

  def radio(%Field{} = field, choice) do
    name = format_name(field.name, field.source)

    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(:radio)
      |> put_value(choice[:value])
      |> put_checked_match(get_checked(choice[:value], field.value))

    input_html = tag(:input, tag_opts) |> safe_to_string

    dummy_label_html = content_tag(:label, for: name) do
      ""
    end |> safe_to_string

    main_label_html = content_tag(:label, for: name) do
      [input_html, choice[:text]] |> raw
    end |> safe_to_string

    wrap_html = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end |> safe_to_string

    append_html(field, wrap_html)
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="checkbox"s
  """
  def checkboxes(%Field{} = field) do
    name = format_name(field.name, field.source)

    empty_value =
      case field.opts[:empty_value] do
        nil -> ""
        val -> tag(:input, [type: :hidden, value: val, name: name]) |> safe_to_string
      end

    field = prepend_html(field, empty_value)

    Enum.reduce(get_choices(field), field, fn(choice, acc) ->
      checkbox(acc, choice)
    end)
  end

  @doc """
  Renders a checkbox.

  This is for multiple checkboxes. Single checks are
  handled through `input(:checkbox, ...)`
  """
  def checkbox(%Field{form_type: :create, value: nil} = field, choice) do
    name = format_name(field.name, field.source)

    tag_opts =
      Keyword.new
      |> put_name("#{name}[]")
      |> put_type(:checkbox)
      |> put_value(choice[:value])
      |> put_checked_match(get_checked(choice[:value], field.opts[:default]))

    input_html = tag(:input, tag_opts) |> safe_to_string

    dummy_label_html = content_tag(:label, for: name) do
      ""
    end |> safe_to_string

    main_label_html = content_tag(:label, for: name) do
      [input_html, choice[:text]] |> raw
    end |> safe_to_string

    wrap_html = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end |> safe_to_string

    append_html(field, wrap_html)
  end

  def checkbox(%Field{opts: %{is_selected: is_checked_fun}} = field, choice) do
    name = format_name(field.name, field.source)

    tag_opts =
      Keyword.new
      |> put_name("#{name}[]")
      |> put_type(:checkbox)
      |> put_value(choice[:value])
      |> put_is_checked_fun(is_checked_fun, choice[:value], field.value)

    input_html = tag(:input, tag_opts) |> safe_to_string

    dummy_label_html = content_tag(:label, for: name) do
      ""
    end |> safe_to_string

    main_label_html = content_tag(:label, for: name) do
      [input_html, choice[:text]] |> raw
    end |> safe_to_string

    wrap_html = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end |> safe_to_string

    append_html(field, wrap_html)
  end

  def checkbox(%Field{} = field, choice) do
    name = format_name(field.name, field.source)

    tag_opts =
      Keyword.new
      |> put_name("#{name}[]")
      |> put_type(:checkbox)
      |> put_value(choice[:value])
      |> put_checked_match(get_checked(choice[:value], field.value))

    input_html = tag(:input, tag_opts) |> safe_to_string

    dummy_label_html = content_tag(:label, for: name) do
      ""
    end |> safe_to_string

    main_label_html = content_tag(:label, for: name) do
      [input_html, choice[:text]] |> raw
    end |> safe_to_string

    wrap_html = content_tag(:div, []) do
      [dummy_label_html, main_label_html] |> raw
    end |> safe_to_string

    append_html(field, wrap_html)
  end

  @doc """
  Iterates through `opts` :choices key, rendering options for the select
  """
  def options(%Field{} = field) do
    Enum.reduce(get_choices(field), field, fn(choice, acc) ->
      option(acc, choice)
    end)
  end

  def option(%Field{form_type: :update, opts: %{is_selected: is_selected_fun}} = field, choice) do
    tag_opts =
      Keyword.new
      |> put_value(choice[:value])
      |> put_is_selected_fun(is_selected_fun, choice[:value], field.value)

    html = content_tag(:option, tag_opts) do
      choice[:text] |> raw
    end |> safe_to_string

    append_html(field, html)
  end

  def option(%Field{form_type: :update} = field, choice) do
    tag_opts =
      Keyword.new
      |> put_value(choice[:value])
      |> put_selected(get_selected(choice[:value], field.value))

    html = content_tag(:option, tag_opts) do
      choice[:text] |> raw
    end |> safe_to_string

    append_html(field, html)
  end

  # no `value` - :create - match `choice_value` to `default`
  def option(%Field{form_type: :create, value: nil} = field, choice) do
    tag_opts =
      Keyword.new
      |> put_value(choice[:value])
      |> put_selected(get_selected(choice[:value], field.opts[:default]))

    html = content_tag(:option, tag_opts) do
      choice[:text] |> raw
    end |> safe_to_string

    append_html(field, html)
  end

  def option(%Field{form_type: :create} = field, choice) do
    tag_opts =
      Keyword.new
      |> put_value(choice[:value])
      |> put_selected(get_selected(choice[:value], field.value))

    html = content_tag(:option, tag_opts) do
      choice[:text] |> raw
    end |> safe_to_string

    append_html(field, html)
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
  def select(%Field{} = field) do
    name = format_name(field.name, field.source)
    opts = Map.delete(field.opts, :default)
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_class(opts)

    case opts[:multiple] do
      nil  ->
        html = content_tag(:select, tag_opts) do
          field.html |> raw
        end |> safe_to_string
        put_html(field, html)
      true ->
        html = content_tag(:select, [name: "#{name}[]", multiple: true]) do
          field.html |> raw
        end |> safe_to_string
        put_html(field, html)
    end
  end

  @doc """
  Single checkbox
  """
  def input(%Field{type: :checkbox} = field) do
    name = format_name(field.name, field.source)
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_value("true")
      |> put_type(:checkbox)
      |> put_placeholder(field)
      |> put_class(field.opts)
      |> put_checked(field.value, field.opts)

    hidden_tag = tag(:input, [name: name, type: :hidden, value: "false"]) |> safe_to_string
    input_tag  = tag(:input, tag_opts) |> safe_to_string

    prepend_html(field, [hidden_tag, input_tag])
  end

  def input(%Field{form_type: :update} = field) do
    field
    |> delete_in_opts(:default)
    |> put_in_field(:form_type, :create)
    |> input
  end

  def input(field) do
    name = format_name(field.name, field.source)
    tag_opts =
      Keyword.new
      |> put_name(name)
      |> put_type(field.type)
      |> put_value(field.value, field.opts)
      |> put_slug_from(name, field.opts)
      |> put_placeholder(field)
      |> put_class(field.opts)
      |> put_tags(field.opts)

    html = tag(:input, tag_opts) |> safe_to_string
    prepend_html(field, html)
  end

  @doc """
  Renders a label for `name`, with `class` and `text` as the
  label's content.
  """
  @spec add_label(Field.t) :: Field.t
  def add_label(%Field{type: :checkbox, opts: %{multiple: false}} = field) do
    name = format_name(field.name, field.source)
    label_text = get_label(field)

    text =
      if label_text do
        [field.html|label_text]
      else
        field.html
      end

    html = content_tag(:label, for: name, class: field.opts[:label_class]) do
      raw(text)
    end |> safe_to_string

    put_html(field, html)
  end

  def add_label(%Field{} = field) do
    name = format_name(field.name, field.source)
    text = get_label(field)

    if text do
      html = content_tag(:label, for: name, class: field.opts[:label_class]) do
        text |> raw
      end |> safe_to_string
      prepend_html(field, html)
    else
      field
    end
  end

  @doc """
  Add a confirm field if `opts.confirm` is true.
  """
  def add_confirm(%Field{opts: %{confirm: true}} = field) do
    confirm_i18n = gettext("Confirm")

    confirm_field =
      field
      |> put_html(nil)
      |> put_in_opts(:label, "#{confirm_i18n} #{get_label(field)}")
      |> put_in_opts(:placeholder, "#{confirm_i18n} #{get_label(field)}")
      |> put_in_field(:name, :"#{field.name}_confirmation")
      |> input
      |> add_label
      |> wrap_in_form_group

    append_html(field, confirm_field.html)
  end

  def add_confirm(field) do
    field
  end

  @doc """
  Returns a div classed as `form-group` (used in bootstrap).

  Sets classes:

    * `required` -- if the wrapped field is marked such
    * `has-error` -- if the field is found in `errors`
  """
  @spec wrap_in_form_group(Field.t) :: Field.t
  def wrap_in_form_group(field) do
    classes = [class: get_group_classes(field.opts, field.errors)]

    html = content_tag(:div, classes) do
      [field.html, render_errors(field.errors), render_help_text(field)] |> raw
    end |> safe_to_string

    put_html(field, html)
  end

  def wrap_in_div(field, class \\ "form-row") do
    if field.opts[:in_fieldset] do
      field
    else
      html = content_tag(:div, class: class) do
        raw(field.html)
      end |> safe_to_string

      put_html(field, html)
    end
  end

  @doc """
  Renders `help_text` in a nicely formatted div.
  """
  @spec render_help_text(Field.t) :: String.t
  def render_help_text(%Field{opts: %{help_text: help_text}} = f) do
    IO.warn("""
    using help_text from form macros is deprecated.

    Set the help text in the schema's meta instead:

        # #{inspect f.schema}
        use Brando.Meta.Schema, [
          ...
          help: [
            #{f.name}: gettext("#{help_text}")
          ]
        ]
    """)
    do_render_help_text(help_text)
  end

  def render_help_text(%Field{schema: nil, name: _}) do
    do_render_help_text("")
  end

  def render_help_text(%Field{schema: schema, name: name}) do
    do_render_help_text(schema.__help_for__(name) || "")
  end

  defp do_render_help_text("") do
    ""
  end

  defp do_render_help_text(help_text) do
    html =
      content_tag(:div, class: "help") do
        [content_tag(:i, " ", class: "fa fa-fw fa-question-circle"),
         content_tag(:span, help_text)]
      end

    safe_to_string(html)
  end

  @doc """
  Renders `errors` in a nicely formatted div by calling parse_error/1
  on each error in the `errors` list.
  """
  @spec render_errors(Keyword.t) :: String.t
  def render_errors(nil), do: ""
  def render_errors(errors) when is_list(errors) do
    for error <- errors do
      content_tag(:div, class: "error") do
        [content_tag(:i, " ", class: "fa fa-exclamation-circle"),
         parse_error(error)]
      end |> safe_to_string
    end
  end

  @doc """
  Translate errors
  """
  @spec parse_error(String.t | {String.t, integer}) :: String.t
  def parse_error({"can't be blank", _}), do:
    gettext("can't be blank")
  def parse_error({"must be unique", _}), do:
    gettext("must be unique")
  def parse_error({"has invalid format", _}), do:
    gettext("has invalid format")
  def parse_error({"is invalid", _}), do:
    gettext("is invalid")
  def parse_error({"is reserved", _}), do:
    gettext("is reserved")
  def parse_error({"has already been taken", _}), do:
    gettext("has already been taken")
  def parse_error({"should be at least %{count} character(s)", [count: len]}), do:
    gettext("should be at least %{count} characters", count: len)
  def parse_error({"should be at least %{count} characters", [count: len]}), do:
    gettext("should be at least %{count} characters", count: len)
  def parse_error(error), do:
    is_binary(error) && error || inspect(error)

  def fieldset_open_tag(nil, _in_fieldset), do:
    ~s(<fieldset><div class="form-row">)

  def fieldset_open_tag(legend, _in_fieldset), do:
    ~s(<fieldset><legend><br>#{legend}</legend><div class="form-row">)

  def fieldset_close_tag, do:
    ~s(</div></fieldset>)

  defp put_slug_from(tag_opts, name, opts) do
    case opts[:slug_from] do
      nil -> tag_opts
      slug_from ->
         caps = Regex.named_captures(~r/(?<form_name>\w*)\[(\w*)\]/, name)
         Keyword.put(tag_opts, :data_slug_from,
                     "#{caps["form_name"]}[#{slug_from}]")
    end
  end

  defp put_placeholder(tag_opts, field) do
    case get_placeholder(field) do
      nil -> tag_opts
      placeholder -> Keyword.put(tag_opts, :placeholder, placeholder)
    end
  end

  defp put_class(tag_opts, nil) do
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
    if is_selected_fun.(choice_value, value) do
      Keyword.put(tag_opts, :selected, true)
    else
      tag_opts
    end
  end

  defp put_is_checked_fun(tag_opts, is_checked_fun, choice_value, value) do
    if is_checked_fun.(choice_value, value) do
      Keyword.put(tag_opts, :checked, true)
    else
      tag_opts
    end
  end

  defp put_checked(tag_opts, value, opts) do
    if checked?(value, opts) do
      Keyword.put(tag_opts, :checked, "checked")
    else
      tag_opts
    end
  end

  defp put_checked_match(tag_opts, match) do
    if match do
      Keyword.put(tag_opts, :checked, true)
    else
      tag_opts
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
  def get_placeholder(%{opts: %{type: :submit}}) do
    nil
  end
  def get_placeholder(%{opts: %{type: :file}}) do
    nil
  end
  def get_placeholder(%{opts: %{placeholder: placeholder}}) do
    placeholder
  end
  def get_placeholder(%{name: name, schema: schema}) do
    schema.__field__(name)
  end
  def get_placeholder(%{opts: %{placeholder: nil}}) do
    nil
  end
  def get_placeholder(_) do
    nil
  end

  @doc """
  Parse and return `opts` looking for label
  """
  def get_label(%Field{opts: %{label: label_text}}) do
    label_text
  end
  def get_label(%Field{name: nil, schema: nil}) do
    nil
  end
  def get_label(%Field{name: name, schema: schema}) do
    schema.__field__(name)
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
  def get_choices(%Field{opts: %{choices: fun}}) do
    apply(fun, [])
  end
  def get_choices(_) do
    nil
  end

  defp get_img_preview(nil), do: ""
  defp get_img_preview(value) do
    content_tag(:div, class: "image-preview") do
      raw(tag(:img, [src: img_url(value, :thumb, prefix: media_url())]))
    end |> safe_to_string
  end

  defp format_name(name, form_source) do
    "#{form_source}[#{name}]"
  end
end
