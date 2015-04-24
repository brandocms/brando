defmodule Brando.Form.Fields do
  @moduledoc """
  A set of functions for rendering form fields. These are all called
  from the `Brando.Form` module, and handled through `Brando.Form.get_form/4`
  """
  @doc """
  Renders file field. Wraps the field with a label and row span
  """
  def render_field(form_type, name, :file, opts, value, errors) do
    __file__(form_type, name, value, errors, opts)
    |> __concat__(__label__(name, opts[:label_class], opts[:label]))
    |> __form_group__(name, opts, errors)
    |> __data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Render textarea.
  Pass a form_group_class to ensure we don't set height on wrapper.
  """
  def render_field(form_type, name, :textarea, opts, value, errors) do
    opts = Keyword.put(opts, :form_group_class, "no-height")
    __textarea__(form_type, name, value, errors, opts)
    |> __concat__(__label__(name, opts[:label_class], opts[:label]))
    |> __form_group__(name, opts, errors)
    |> __data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Render group of radio buttons.
  """
  def render_field(form_type, name, :radio, opts, value, errors) do
    render_radios(form_type, name, opts, value, errors)
    |> Enum.join("")
    |> __concat__(__label__(name, opts[:label_class], opts[:label]))
    |> __form_group__(name, opts, errors)
    |> __data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Render checkboxes. Both groups and singles.
  """
  def render_field(form_type, name, :checkbox, opts, value, errors) do
    if opts[:multiple] do
      render_checks(form_type, name, opts, value, errors)
      |> __concat__(__label__(name, opts[:label_class], opts[:label]))
      |> __form_group__(name, opts, errors)
      |> __data_row_span__(opts[:in_fieldset])
    else
      __concat__(__label__(name, opts[:label_class], __input__(:checkbox, form_type, name, value, errors, opts) <> opts[:label]), __label__(name, "", ""))
      |> __div__("checkbox")
      |> __form_group__(name, opts, errors)
      |> __data_row_span__(opts[:in_fieldset])
    end
  end

  @doc """
  Render select. Calls `render_options`
  """
  def render_field(form_type, name, :select, opts, value, errors) do
    choices = render_options(form_type, opts, value, errors)
    __select__(form_type, name, choices, opts, value, errors)
    |> __concat__(__label__(name, opts[:label_class], opts[:label]))
    |> __form_group__(name, opts, errors)
    |> __data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Render submit button
  """
  def render_field(form_type, name, :submit, opts, _value, errors) do
    __input__(:submit, form_type, name, opts[:text], errors, opts)
    |> __form_group__(name, opts, errors)
    |> __data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Render fieldset open
  """
  def render_field(_form_type, _name, :fieldset, opts, _value, _errors) do
    __fieldset_open__(opts[:legend], opts[:row_span])
  end

  @doc """
  Render fieldset close
  """
  def render_field(_form_type, _name, :fieldset_close, _opts, _value, _errors) do
    __fieldset_close__()
  end

  @doc """
  Render text/password/email (catchall)
  """
  def render_field(form_type, name, input_type, opts, value, errors) do
    __input__(input_type, form_type, name, value, errors, opts)
    |> __concat__(__label__(name, opts[:label_class], opts[:label]))
    |> __form_group__(name, opts, errors)
    |> __data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Iterates through `opts` :choices key, rendering options for the select
  """
  def render_options(form_type, opts, value, _errors) do
    for choice <- get_choices(opts[:choices]) do
      __option__(form_type, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="radio"s
  """
  def render_radios(form_type, name, opts, value, _errors) do
    for choice <- get_choices(opts[:choices]) do
      __radio__(form_type, name, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="checkbox"s
  """
  def render_checks(form_type, name, opts, value, _errors) do
    checks = for choice <- get_choices(opts[:choices]) do
      __checkbox__(form_type, name, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
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
  @spec __form_group__(String.t, String.t, Keyword.t, Keyword.t) :: String.t
  def __form_group__(contents, _name, opts, errors) do
    ~s(<div data-field-span="1" class="form-group#{get_form_group_class(opts[:form_group_class])}#{get_required(opts[:required])}#{get_has_error(errors)}">
      #{contents}
      #{__render_errors__(errors)}
      #{__render_help_text__(opts[:help_text])}
    </div>)
  end

  @doc """
  Renders `help_text` in a nicely formatted div.
  """
  @spec __render_help_text__(String.t | nil) :: String.t
  def __render_help_text__(nil), do: ""
  def __render_help_text__(help_text) do
    ~s(<div class="help"><i class="fa fa-fw fa-question-circle"> </i><span>#{help_text}</span></div>)
  end

  @doc """
  Renders `errors` in a nicely formatted div by calling __parse_error__/1
  on each error in the `errors` list.
  """
  @spec __render_errors__(Options.t | Keyword.t) :: String.t
  def __render_errors__([]), do: ""
  def __render_errors__(errors) when is_list(errors) do
    for error <- errors do
      ~s(<div class="error"><i class="fa fa-exclamation-circle"> </i> #{__parse_error__(error)}</div>)
    end
  end

  @doc """
  Translate errors
  """
  @spec __parse_error__(String.t | {String.t, integer}) :: String.t
  def __parse_error__(error) do
    case error do
      "can't be blank"     -> "Feltet er påkrevet."
      "must be unique"     -> "Feltet må være unikt. Verdien finnes allerede i databasen."
      "has invalid format" -> "Feltet har feil format."
      {"should be at least %{count} characters", length} -> "Feltets verdi er for kort. Må være > #{length} tegn."
      err                  -> inspect(err)
    end
  end

  @doc """
  Concats `wrapped_field` and `label`, with `label` being
  the first
  """
  @spec __concat__(String.t, String.t) :: String.t
  def __concat__(wrapped_field, label) do
    label <> wrapped_field
  end

  @doc """
  Returns a div with class=`class` and `content`
  """
  @spec __div__(String.t, String.t) :: String.t
  def __div__(contents, class) do
    ~s(<div class="#{class}">#{contents}</div>)
  end

  @doc """
  Wraps `field` in a div with `wrapper_class` as class.
  """
  @spec __wrap__(String.t, String.t | nil) :: String.t
  def __wrap__(field, nil), do: field
  def __wrap__(field, wrapper_class) do
    ~s(<div class="#{wrapper_class}">#{field}</div>)
  end

  @doc """
  Renders a label for `name`, with `class` and `text` as the
  label's content.
  """
  @spec __label__(String.t, String.t, String.t) :: String.t
  def __label__(name, class, text) do
    ~s(<label for="#{name}" class="#{class}">#{text}</label>)
  end

  @doc """
  Render a file field for :update. If we have `value`, try to render
  an img element with a thumbnail.
  """
  @spec __file__(atom, String.t, String.t, Options.t | Keyword.t, Options.t | Keyword.t) :: String.t
  def __file__(:update, name, value, _errors, opts) do
    opts = List.delete(opts, :default)
    img =
      if value do
        ~s(<div class="image-preview"><img src="#{Brando.HTML.media_url(Brando.Images.Helpers.img(value, :thumb))}" /></div>)
      else
        ""
      end
   img <> __file__(:create, name, value, _errors, opts)
  end

  @doc """
  Render a file field for :create.
  """
  def __file__(:create, name, _value, _errors, opts) do
    ~s(<input name="#{name}" type="file"#{get_placeholder(opts[:placeholder])}#{get_class(opts[:class])} />)
  end

  @doc """
  Render a textarea field for :update.
  """
  @spec __textarea__(atom, String.t, String.t, Options.t | Keyword.t, Options.t | Keyword.t) :: String.t
  def __textarea__(:update, name, value, _errors, opts) do
    opts = List.delete(opts, :default)
    __textarea__(:create, name, value, _errors, opts)
  end

  @doc """
  Render a textarea field for :create.
  """
  def __textarea__(_form_type, name, [], _errors, opts) do
    default = if opts[:default], do: opts[:default], else: ""
    ~s(<textarea name="#{name}"#{get_class(opts[:class])}>#{default}</textarea>)
  end
  def __textarea__(_form_type, name, value, _errors, opts) when is_map(value) do
    ~s(<textarea name="#{name}"#{get_class(opts[:class])}>#{Poison.encode!(value)}</textarea>)
  end
  def __textarea__(_form_type, name, value, _errors, opts) do
    ~s(<textarea name="#{name}"#{get_class(opts[:class])}>#{value}</textarea>)
  end

  @doc """
  Renders a select tag. Passes `choices` to __tag__/4

  ## Parameters:

    * `name`: name of field
    * `choices`: list of choices to be iterated as options
    * `opts`: list with options for the field
    * `_value`: empty
    * `_errors`: empty
  """
  def __select__(_, name, choices, opts, _value, _errors) do
    opts = List.delete(opts, :default)
    case opts[:multiple] do
      nil  -> __tag__("select", name, choices, opts[:class])
      true -> ~s(<select name="#{name}[]" multiple>#{choices}</select>)
    end
  end

  def __option__(form_type, choice_value, choice_text, value, default, is_selected_fun \\ nil)
  def __option__(:update, choice_value, choice_text, value, _default, is_selected_fun) do
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
  def __option__(:create, choice_value, choice_text, [], default, _) do
    ~s(<option value="#{choice_value}"#{get_selected(choice_value, default)}>#{choice_text}</option>)
  end

  def __option__(:create, choice_value, choice_text, value, _default, _) do
    ~s(<option value="#{choice_value}"#{get_selected(choice_value, value)}>#{choice_text}</option>)
  end

  def __radio__(form_type, name, choice_value, choice_text, value, default, is_selected_fun \\ nil)
  def __radio__(:create, name, choice_value, choice_text, [], default, _) do
    ~s(<div class="radio"><label for="#{name}"></label><label for="#{name}"><input name="#{name}" type="radio" value="#{choice_value}"#{get_checked(choice_value, default)} />#{choice_text}</label></div>)
  end

  def __radio__(_, name, choice_value, choice_text, value, _default, is_selected_fun) do
    if is_selected_fun do
      checked = case is_selected_fun.(choice_value, value) do
        true  -> " " <> "checked"
        false -> ""
      end
    else
      checked = get_checked(choice_value, value)
    end
    ~s(<div class="radio"><label for="#{name}"></label><label for="#{name}"><input name="#{name}" type="radio" value="#{choice_value}"#{checked} />#{choice_text}</label></div>)
  end

  def __checkbox__(form_type, name, choice_value, choice_text, value, default, is_selected_fun \\ nil)
  def __checkbox__(:create, name, choice_value, choice_text, [], default, _) do
    ~s(<div class="checkboxes"><label for="#{name}[]"></label><label for="#{name}[]"><input name="#{name}[]" type="checkbox" value="#{choice_value}"#{get_checked(choice_value, default)} />#{choice_text}</label></div>)
  end

  def __checkbox__(_, name, choice_value, choice_text, value, _default, is_selected_fun) do
    if is_selected_fun do
      checked = case is_selected_fun.(choice_value, value) do
        true  -> " " <> "checked"
        false -> ""
      end
    else
      checked = get_checked(choice_value, value)
    end
    ~s(<div class="checkboxes"><label for="#{name}[]"></label><label for="#{name}[]"><input name="#{name}[]" type="checkbox" value="#{choice_value}"#{checked} />#{choice_text}</label></div>)
  end

  def __fieldset_open__(nil, in_fieldset) do
    ~s(<fieldset><div data-row-span="#{in_fieldset}">)
  end

  def __fieldset_open__(legend, in_fieldset) do
    ~s(<fieldset><legend><br>#{legend}</legend><div data-row-span="#{in_fieldset}">)
  end

  def __fieldset_close__() do
    ~s(</div></fieldset>)
  end

  def __data_row_span__(content, nil) do
    ~s(<div data-row-span="1">#{content}</div>)
  end

  def __data_row_span__(content, _span) do
    content
  end

  def __input__(:checkbox, _form_type, name, value, _errors, opts) do
    checked =
      case value do
        v when v in ["on", true, "true"] -> " " <> "checked=\"checked\""
        v when v in [false, nil, "false"] -> ""
        [] ->
          case opts[:default] do
            true  -> " " <> "checked=\"checked\""
            false -> ""
            nil   -> ""
          end
      end
    ~s(<input name="#{name}" type="hidden" value="false">
       <input name="#{name}" value="true" type="checkbox"#{get_placeholder(opts[:placeholder])}#{get_class(opts[:class])}#{checked} />)
  end

  def __input__(input_type, :update, name, value, _errors, opts) do
    opts = List.delete(opts, :default)
   __input__(input_type, :create, name, value, _errors, opts)
  end

  def __input__(input_type, _form_type, name, value, _errors, opts) do
    ~s(<input name="#{name}" type="#{input_type}"#{get_slug_from(name, opts)}#{get_val(value, opts[:default])}#{get_placeholder(opts[:placeholder])}#{get_class(opts[:class])} />)
  end

  def __tag__(tag, name, contents, class) do
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
    if cv in v, do: " " <> "checked"
  end
  def get_checked(_, _), do: ""

  @doc """
  If `true`, returns required
  """
  def get_required(true), do: " " <> "required"
  def get_required(false), do: ""
  def get_required(nil), do: ""

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
  def get_placeholder(placeholder), do: " " <> "placeholder=\"#{placeholder}\""

  @doc """
  If `class` is not nil, returns class
  """
  def get_class(nil), do: ""
  def get_class(class), do: " " <> "class=\"#{class}\""

  @doc """
  If `value` is not nil, returns value.
  """
  def get_val([]), do: ""
  def get_val(nil), do: ""
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
  def get_choices(fun), do: apply(fun, [])
end