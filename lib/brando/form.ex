defmodule Brando.Form do
  @moduledoc """
  Brando.Form exposes some macros and helpers to help create
  form schemas for generating HTML forms.

  ## Usage

      use Brando.Form

  """
  alias Brando.Utils

  @type form_opts :: [{:helper, atom} | {:class, String.t}]

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

      form "user", [action: :admin_user_path, class: "grid-form"] do
        field :full_name, :text,
          [required: true,
           label: "Full name",
        submit "Lagre",
          [class: "btn btn-success"]
      end

  ## Options

  This macro accepts a set of options:

    * `action`: An atom representing the helper function that will
      get the form's action. I.E: :admin_user_path.
    * `class`: Class name for the form
  """

  @spec form(String.t, form_opts, [do: Macro.t]) :: Macro.t
  defmacro form(source, opts \\ [], block)
  defmacro form(source, opts, [do: block]) do
    quote do
      @form_fields    []
      @form_source    unquote(source)
      @form_helper    unquote(opts[:helper])
      @form_class     unquote(opts[:class] || "")
      @form_multipart false


      unquote(block)

      @doc """
      Returns a rendered form marked safe for the module.

      ## Options:

        * `type`   - The form type
          Example: `type: :create` or `type: :update`
        * `action` - Action the form is performing.
          Example: `action: :create` or `action: :update_all`
        * `params` - Any parameters to the :action function helper.
          Example: `params: to_string(@id)`
        * `values` - Pass @values through the form builder
          Example: `values: @user`
        * `errors` - Pass @errors through the form builder

      ## Example:

          <%= get_form(type: :create, action: :create, params: [], values: @user, errors: @errors) %>

      """
      def get_form(type: form_type, action: action, params: params, values: values, errors: errors) do
        form = [helper: @form_helper, source: @form_source,
                multipart: @form_multipart, class: @form_class]
        render_fields(@form_source, @form_fields, form_type, params, values, errors)
        |> Enum.join("\n")
        |> render_form(form_type, @form_helper, action, params, form)
        |> safe
      end

      defp render_form(fields, form_type, action_fun, action, params, form) do
        csrf_tag = get_csrf(form_type)
        method = get_method(form_type)
        method_tag = method_override(form_type)
        action = " " <> "action=\"#{get_action(action_fun, action, params)}\""
        class  = " " <> "class=\"#{form[:class]}\""
        role   = " " <> "role=\"form\""
        multipart =
          if form[:multipart], do: ~s( enctype="multipart/form-data"), else: ""
        ~s(<form#{class}#{role}#{action}#{method}#{multipart}>#{csrf_tag}#{method_tag}#{fields}</form>)
      end

      @doc """
      Reduces all form_fields and returns a list of each individual
      field as HTML. Builds the correct name for the field by joining
      `@form_source` with `name`. Gets any value or errors for the field.
      """
      def render_fields(form_source, form_fields, form_type, params, values, errors) do
        values = Utils.to_string_map(values)
        if values == nil, do: values = []
        if errors == nil, do: errors = []
        Enum.reduce(form_fields, [], fn ({name, opts}, acc) ->
          acc = [render_field(form_type, "#{form_source}[#{name}]", opts[:type],
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
        * `slug_from` - :name
          Automatically slugs with `:name` as source.
        * `help_text` - "Help text for field"
        * `placeholder` - "Placeholder for field"
        * `default` - Default value. Can also be a function like
                      `&__MODULE__.default_func/0`

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
        * `empty_value`: Value to set if none of the boxes are checked.
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

  @doc false
  defmacro fieldset(legend \\ nil, [do: block]) do
    quote do
      fieldset_open(unquote(legend))
      unquote(block)
      fieldset_close
    end
  end

  @doc false
  defmacro fieldset_open(legend) do
    quote do
      Brando.Form.fieldset_open(__MODULE__, unquote(legend))
    end
  end

  @doc """
  Marks the field as a fieldset tag opening. This means we are
  :in_fieldset, which we need for proper form markup.
  """
  def fieldset_open(mod, legend) do
    fields = Module.get_attribute(mod, :form_fields)
    Module.put_attribute(mod, :in_fieldset, true)
    Module.put_attribute(mod, :form_fields, [{:"fs", [type: :fieldset] ++ [legend: legend]}|fields])
  end

  @doc false
  defmacro fieldset_close() do
    quote do
      Brando.Form.fieldset_close(__MODULE__)
    end
  end

  @doc """
  Marks the field as a fieldset tag closing. This means we are no
  longer :in_fieldset.
  """
  def fieldset_close(mod) do
    name = String.to_atom("fs" <> to_string(:erlang.phash2(:os.timestamp)))
    fields = Module.get_attribute(mod, :form_fields)
    Module.put_attribute(mod, :form_fields, [{name, [type: :fieldset_close]}|fields])
    Module.put_attribute(mod, :in_fieldset, nil)
  end

  @doc false
  defmacro submit(text \\ "Submit", opts \\ []) do
    quote do
      Brando.Form.__submit__(__MODULE__, unquote(text), unquote(opts))
    end
  end

  @doc """
  Marks the field as a submit button.
  """
  def __submit__(mod, text, opts) do
    name = if opts[:name], do: opts[:name], else: :submit
    fields = Module.get_attribute(mod, :form_fields)
    clash = Enum.any?(fields, fn {prev, _} -> name == prev end)
    if clash, do:
      raise(ArgumentError, message: "submit field `#{name}` was already set on schema")
    Module.put_attribute(mod, :form_fields, [{name, [type: :submit, text: text] ++ opts}|fields])
  end

  defp check_type!(type) when type in [:text, :password, :select, :email,
                                       :checkbox, :file, :radio, :textarea], do: :ok

  defp check_type!(type), do:
    raise(ArgumentError, message: "`#{Macro.to_string(type)}` is not a valid field type")

  @doc """
  Evals the quoted action function, normally a path helper,
  and returns the result
  """
  def get_action(fun, action, params \\ nil) do
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
  Returns a csrf input tag
  """
  def get_csrf(form_type) when form_type in [:update, :delete, :create], do:
    ~s(<input name="_csrf_token" type="hidden" value="#{Phoenix.Controller.get_csrf_token()}">)
  def get_csrf(_), do: ""

  @doc """
  Checks `values` for name and returns value if found.
  If not it returns an empty list
  """
  def get_value([], _), do: []
  def get_value(values, name) do
    case Map.fetch(values, Atom.to_string(name)) do
      {:ok, val} -> val
      :error     -> []
    end
  end

  @doc """
  Checks `errors` for name and returns the error if found.
  If not it returns an empty list.
  """
  def get_errors([], _), do: []
  def get_errors(errors, name) do
    case Keyword.get_values(errors, name) do
      []     -> []
      values -> values
    end
  end
end