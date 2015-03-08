defmodule Brando.Form do
  @moduledoc """
  Brando.Form exposes some macros and helpers to help create
  form schemas for generating HTML forms.

  ## Usage

      use Brando.Form

  """
  alias Brando.Form.Fields, as: F
  alias Brando.Utils

  defmacro __using__(_) do
    quote do
      import Brando.Form
      import Brando.Form.Fields
      import Phoenix.HTML, only: [safe: 1]
    end
  end

  @doc """
  Defines a form that is bound to the module through multiple
  module constants.

  ## Usage

      form "user", [action: :admin_user_path] do
        field :full_name, :text,
          [required: true,
           label: "Full name",
        submit "Lagre",
          [class: "btn btn-default"]
      end

  ## Options

  This macro accepts a set of options:

    * `action`: An atom representing the helper function that will
      get the form's action. I.E: :admin_user_path.
  """
  defmacro form(source, opts \\ [], block)
  defmacro form(source, opts, [do: block]) do
    quote do
      @form_source unquote(source)
      @form_helper unquote(opts[:helper])
      @form_class unquote(opts[:class] || "")
      @form_multipart false
      @form_fields []

      unquote(block)

      @doc """
      Returns a rendered form marked safe for the module.

      ## Options:

        * `action` - Action the form is performing.
          Example: `action: :create`
        * `params` - Any parameters to the :action function helper.
          Example: `params: to_string(@id)`
        * `values` - Pass @values through the form builder
          Example: `values: @user`
        * `errors` - Pass @errors through the form builder

      ## Example:

          <%= get_form(action: :create, params: [], values: @user, errors: @errors) %>

      """
      def get_form(action: action, params: params, values: values, errors: errors) do
        form = [helper: @form_helper, source: @form_source,
                multipart: @form_multipart, class: @form_class]
        render_fields(@form_source, @form_fields, action, params, values, errors)
        |> Enum.join("\n")
        |> render_form(@form_helper, action, params, form)
        |> safe
      end

      defp render_form(fields, action_fun, action, params, form) do
        method = get_method(action)
        method_tag = method_override(action)
        action = " " <> "action=\"#{get_action(action_fun, action, params)}\""
        class  = " " <> "class=\"#{form[:class]}\""
        role   = " " <> "role=\"form\""
        if form[:multipart], do: multipart = ~s( enctype="multipart/form-data"),
        else: multipart = ""
        ~s(<form#{class}#{role}#{action}#{method}#{multipart}>#{method_tag}#{fields}</form>)
      end

      @doc """
      Reduces all form_fields and returns a list of each individual
      field as HTML. Builds the correct name for the field by joining
      `@form_source` with `name`. Gets any value or errors for the field.
      """
      def render_fields(form_source, form_fields, action, params, values, errors) do
        values = Utils.to_string_map(values)
        if values == nil, do: values = []
        if errors == nil, do: errors = []
        Enum.reduce(form_fields, [], fn ({name, opts}, acc) ->
          acc = [render_field(action, "#{form_source}[#{name}]", opts[:type],
                              opts, get_value(values, name),
                              get_errors(errors, name))|acc]
        end)
      end
    end
  end

  @doc """
  Macro for marking field as `type`.

  ## Parameters

    * `name`: The field name. Used in HTML attribute. Must be unique
              per form.

    * `type`: The type of the field.
      * `:text`, `:email`, `:password` -

        # Options
        * `required` - true
        * `label` - "Label for field"
        * `help_text` - "Help text for field"
        * `placeholder` - "Placeholder for field"

      * `checkbox` - Standard checkbox

        # Options
        * `multiple` - Multiple checkboxes.
                       Gets labels/values from `choices` option
        * `choices` - &__MODULE__.get_status_choices/0
        * `is_selected` - Pass a function that checks if `value` is selected.
                          The function gets passed the checkbox's value, and
                          the model's value.
                          &__MODULE__.status_is_selected/2
        * `label`: "Label for field"
        * `default`: true/false. Set as a value when using `multiple`.
          - ex: "2"

      * `select` - Select with options through `choices`.

        # Options
        * `multiple` - The select returns multiple options, if true.
        * `choices` - &__MODULE__.get_status_choices/0
                     Points to `get_status_choices/0` function
                     in the module the form was defined.
        * `is_selected` - Pass a function that checks if `value` is selected.
                          The function gets passed the option's value, and
                          the model's value.
                          &__MODULE__.status_is_selected/2
        * `default` - "1"
        * `label` - "Label for the select"

      * `file` - Attach a file to the form. Sets the form to multipart.

        # Options
        * `label` - "Label for file field"

      * `radio` - A group of radio buttons through `choices`

        # Options
        * `choices` - &__MODULE__.get_status_choices/0
        * `label` - Label for the entire group. Each individual radio
                    gets its label from the `choices` function.
        * `label_class` - Label class for the main label.

  """
  defmacro field(name, type \\ :text, opts \\ []) do
    quote do
      Brando.Form.__field__(__MODULE__, unquote(name), unquote(type), unquote(opts))
    end
  end

  @doc """
  Marks the field as a field of some `type`. See docs for `field/3` macro.
  """
  def __field__(mod, name, type, opts) do
    check_type!(type)
    fields = Module.get_attribute(mod, :form_fields)

    if Module.get_attribute(mod, :in_fieldset) do
      opts = [in_fieldset: Module.get_attribute(mod, :in_fieldset)] ++ opts
    end

    clash = Enum.any?(fields, fn {prev, _} -> name == prev end)
    if clash do
      raise ArgumentError, message: "field `#{name}` was already set on schema"
    end

    Module.put_attribute(mod, :form_fields, [{name, [type: type] ++ opts}|fields])

    if type == :file, do: Module.put_attribute(mod, :form_multipart, true)
  end

  defmacro fieldset(opts \\ [], [do: block]) do
    quote do
      fieldset_open(unquote(opts))
      unquote(block)
      fieldset_close
    end
  end

  defmacro fieldset_open(opts) do
    quote do
      Brando.Form.__fieldset_open__(__MODULE__, unquote(opts))
    end
  end

  @doc """
  Marks the field as a <fieldset> tag opening. This means we are
  :in_fieldset, which we need for proper form markup.
  """
  def __fieldset_open__(mod, opts) do
    name = String.to_atom("fs" <> to_string(:erlang.phash2(:os.timestamp)))
    fields = Module.get_attribute(mod, :form_fields)
    Module.put_attribute(mod, :in_fieldset, opts[:row_span])
    Module.put_attribute(mod, :form_fields, [{name, [type: :fieldset] ++ opts}|fields])
  end

  defmacro fieldset_close() do
    quote do
      Brando.Form.__fieldset_close__(__MODULE__)
    end
  end

  @doc """
  Marks the field as a <fieldset> tag closing. This means we are no
  longer :in_fieldset.
  """
  def __fieldset_close__(mod) do
    opts = []
    name = String.to_atom("fs" <> to_string(:erlang.phash2(:os.timestamp)))
    fields = Module.get_attribute(mod, :form_fields)
    Module.put_attribute(mod, :form_fields, [{name, [type: :fieldset_close] ++ opts}|fields])
    Module.put_attribute(mod, :in_fieldset, nil)
  end

  defmacro submit(text \\ "Submit", opts \\ []) do
    quote do
      Brando.Form.__submit__(__MODULE__, unquote(text), unquote(opts))
    end
  end

  @doc """
  Marks the field as a submit button.
  """
  def __submit__(mod, text, opts) do
    if opts[:name], do:
      name = opts[:name],
    else: name = :submit

    fields = Module.get_attribute(mod, :form_fields)

    clash = Enum.any?(fields, fn {prev, _} -> name == prev end)
    if clash do
      raise ArgumentError, message: "submit field `#{name}` was already set on schema"
    end

    Module.put_attribute(mod, :form_fields, [{name, [type: :submit, text: text] ++ opts}|fields])
  end

  defp check_type!(type) when type in [:text, :password, :select, :email,
                                       :checkbox, :file, :radio, :textarea], do: :ok

  defp check_type!(type) do
    raise ArgumentError, message: "`#{Macro.to_string(type)}` is not a valid field type"
  end

  @doc """
  Evals the quoted choices function and returns the result
  """
  def get_choices(fun), do: apply(fun, [])

  @doc """
  Evals the quoted action function, normally a path helper,
  and returns the result
  """
  def get_action(fun, action, params \\ []) do
    apply(Brando.get_helpers, fun, [Brando.get_endpoint(), action, params])
  end

  @doc """
  Returns a HTML input for our method override for `action`
  """
  def method_override(action)
  def method_override(:update), do:
    ~s(<input name="_method" type="hidden" value="patch" />)
  def method_override(:delete), do:
    ~s(<input name="_method" type="hidden" value="delete" />)
  def method_override(_), do: ""

  @doc """
  Returns the correct method for our form's action. This is necessary
  for proper method overriding.
  """
  def get_method(:update), do: " " <> ~s(method="POST")
  def get_method(:delete), do: " " <> ~s(method="POST")
  def get_method(:create), do: " " <> ~s(method="POST")
  def get_method(_), do: " " <> ~s(method="GET")

  @doc """
  Checks `values` for name and returns value if found.
  If not it returns an empty list
  """
  def get_value([], _), do: []
  def get_value(values, name) do
    case Map.fetch(values, Atom.to_string(name)) do
      {:ok, val} -> val
      :error -> []
    end
  end

  @doc """
  Checks `errors` for name and returns the error if found.
  If not it returns an empty list.
  """
  def get_errors([], _), do: []
  def get_errors(errors, name) do
    case Keyword.get_values(errors, name) do
      [] -> []
      values -> values
    end
  end

  @doc """
  Renders field by type. Wraps the field with a label and row span
  """
  def render_field(action, name, :file, opts, value, errors) do
    F.__file__(action, name, value, errors, opts)
    |> F.__concat__(F.__label__(name, opts[:label_class], opts[:label]))
    |> F.__form_group__(name, opts, errors)
    |> F.__data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Render textarea.
  Pass a form_group_class to ensure we don't set height on wrapper.
  """
  def render_field(action, name, :textarea, opts, value, errors) do
    opts = Keyword.put(opts, :form_group_class, "no-height")
    F.__textarea__(action, name, value, errors, opts)
    |> F.__concat__(F.__label__(name, opts[:label_class], opts[:label]))
    |> F.__form_group__(name, opts, errors)
    |> F.__data_row_span__(opts[:in_fieldset])
  end

  def render_field(action, name, :radio, opts, value, errors) do
    render_radios(action, name, opts, value, errors)
    |> Enum.join("")
    |> F.__concat__(F.__label__(name, opts[:label_class], opts[:label]))
    |> F.__form_group__(name, opts, errors)
    |> F.__data_row_span__(opts[:in_fieldset])
  end

  def render_field(action, name, :checkbox, opts, value, errors) do
    if opts[:multiple] do
      render_checks(action, name, opts, value, errors)
      |> Enum.join("")
      |> F.__concat__(F.__label__(name, opts[:label_class], opts[:label]))
      |> F.__form_group__(name, opts, errors)
      |> F.__data_row_span__(opts[:in_fieldset])
    else
      F.__concat__(F.__label__(name, opts[:label_class], F.__input__(:checkbox, action, name, value, errors, opts) <> opts[:label]), F.__label__(name, "", ""))
      |> F.__div__("checkbox")
      |> F.__form_group__(name, opts, errors)
      |> F.__data_row_span__(opts[:in_fieldset])
    end
  end

  def render_field(action, name, :select, opts, value, errors) do
    choices = render_options(action, opts, value, errors)
    F.__select__(action, name, choices, opts, value, errors)
    |> F.__concat__(F.__label__(name, opts[:label_class], opts[:label]))
    |> F.__form_group__(name, opts, errors)
    |> F.__data_row_span__(opts[:in_fieldset])
  end

  def render_field(action, name, :submit, opts, value, errors) do
    F.__input__(:submit, action, name, value, errors, opts)
    |> F.__form_group__(name, opts, errors)
    |> F.__data_row_span__(opts[:in_fieldset])
  end

  def render_field(_action, _name, :fieldset, opts, _value, _errors) do
    F.__fieldset_open__(opts[:legend], opts[:row_span])
  end

  def render_field(_action, _name, :fieldset_close, _opts, _value, _errors) do
    F.__fieldset_close__()
  end

  def render_field(action, name, type, opts, value, errors) do
    F.__input__(type, action, name, value, errors, opts)
    |> F.__concat__(F.__label__(name, opts[:label_class], opts[:label]))
    |> F.__form_group__(name, opts, errors)
    |> F.__data_row_span__(opts[:in_fieldset])
  end

  @doc """
  Iterates through `opts` :choices key, rendering options for the select
  """
  def render_options(action, opts, value, _errors) do
    for choice <- get_choices(opts[:choices]) do
      F.__option__(action, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="radio"s
  """
  def render_radios(action, name, opts, value, _errors) do
    for choice <- get_choices(opts[:choices]) do
      F.__radio__(action, name, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
  end

  @doc """
  Iterates through `opts` :choices key, rendering input type="checkbox"s
  """
  def render_checks(action, name, opts, value, _errors) do
    for choice <- get_choices(opts[:choices]) do
      F.__checkbox__(action, name, choice[:value], choice[:text], value, opts[:default], opts[:is_selected])
    end
  end
end