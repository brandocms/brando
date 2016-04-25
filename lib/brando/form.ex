defmodule Brando.Form do
  @moduledoc ~S"""
  Macros and helpers to help create form schemas for generating HTML forms.

  ## Usage

      use Brando.Form

      form "user", [schema: Brando.User,
                    action: :admin_user_path,
                    class: "grid-form"] do
        field :full_name, :text, [required: false]
        submit :save, [class: "btn btn-success"]
      end

  Set field labels, placeholders and help_text by using your `schema`'s meta.

  See `Brando.Meta.Model` for more info about meta.

  See this module's `Brando.Form.form` and `Brando.Form.field` docs for more.
  """

  @type form_opts :: [{:helper, atom} | {:class, String.t}]

  @valid_field_types [
    :text,
    :password,
    :select,
    :email,
    :checkbox,
    :file,
    :radio,
    :textarea,
    :datetime
  ]

  alias Brando.Form.Field
  alias Brando.Form.Fields
  import Phoenix.HTML.Tag, only: [form_tag: 3]
  import Phoenix.HTML, only: [raw: 1]

  defmacro __using__(_) do
    quote do
      import Brando.Form
      import Brando.Form.Fields
      import Phoenix.HTML, only: [raw: 1]
    end
  end

  @doc """
  Defines a form that is bound to the module through multiple
  module constants.

  ## Usage

      form "user", [action: :admin_user_path, class: "grid-form"] do
        field :full_name, :text, [required: false]
        submit :save, [class: "btn btn-success"]
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
    if Keyword.get(opts, :model) do
      raise "form/3 :model keyword is deprecated. use :schema instead"
    end
    quote do
      @form_opts %{
        class: unquote(opts[:class] || ""),
        helper: unquote(opts[:helper]),
        schema: unquote(opts[:schema]),
        multipart: false,
        source: unquote(source)
      }
      @form_fields []

      def __model__ do
        unquote(source)
      end

      unquote(block)

      @doc """
      Returns a rendered form marked safe for the module.

      ## Options:

        * `type` - The form type
          Example: `type: :create` or `type: :update`
        * `action` - Action the form is performing.
          Example: `action: :create` or `action: :update_all`
        * `params` - Any parameters to the :action function helper.
          Example: `params: to_string(@id)`
        * `changeset`: Model/param changeset.

      ## Example:

          <%= get_form(type: :create, action: :create,
                       params: [], changeset: @changeset) %>

      """
      def get_form(opts) do
        form_type = Keyword.fetch!(opts, :type)
        action = Keyword.fetch!(opts, :action)
        changeset = Keyword.fetch!(opts, :changeset)
        params = Keyword.get(opts, :params, [])

        @form_fields
        |> render_fields(changeset, opts, @form_opts)
        |> render_form(opts, @form_opts)
        |> raw
      end
    end
  end

  @doc """
  Performs rendering of form.

  ## Options

    * `fields`: The rendered form fields we will wrap this form around.
    * `opts`:
      * `form_type`: :create, :update
      * `action`: The action atom passed to `helper`, e.g.: `:create`
      * `params`: Parameters passed to `helper`, e.g.: `to_string(@user.id)`
    * `form_opts`:
      * `class`: Optional class to set on form.
      * `multipart`: Automatically set if we have file fields.
      * `helper`: Helper set in form definition.
  """
  @spec render_form(iodata, Keyword.t | nil, Keyword.t) :: String.t
  def render_form(fields, opts, form_opts) do
    form_type = Keyword.fetch!(opts, :type)
    action = Keyword.fetch!(opts, :action)
    params = Keyword.get(opts, :params, [])
    url = apply_action(form_opts[:helper], action, params)

    form_opts =
      form_opts
      |> Keyword.new
      |> Keyword.drop([:model, :helper, :source])
      |> Keyword.put(:enforce_utf8, true)
      |> Keyword.put(:method, get_method(form_type))
      |> Keyword.put(:role, "form")

    form_opts =
      case Keyword.pop(form_opts, :multipart, false) do
        {false, form_opts} -> form_opts
        {true, form_opts}  -> Keyword.put(form_opts, :multipart, true)
      end

    form_opts =
      case Keyword.pop(form_opts, :class, false) do
        {false, form_opts} -> form_opts
        {class, form_opts} -> Keyword.put(form_opts, :class, class)
      end

    form_tag(url, form_opts, do: raw(fields))
  end

  @doc """
  Reduces all `fields` and returns a list of each individual
  field as HTML. Gets any values or errors for the field.
  """
  def render_fields(fields, changeset, form_opts, %{source: source, schema: schema}) do
    Enum.reduce fields, [], fn ({name, field_opts}, acc) ->
      field = %Field{
        form_type: form_opts[:type],
        source: source,
        name: name,
        schema: schema,
        value: get_value(changeset, name),
        errors: get_errors(changeset, name),
        type: field_opts[:type],
        opts: Enum.into(field_opts, %{})
      } |> Fields.render_field

      [field.html|acc]
    end
  end

  @doc """
  Macro for marking field as `type`.

  ## Parameters

    * `name`: The field name. Used in HTML attribute. Must be unique per form.
    * `type`: The type of the field.

  ## Types

  `:text`, `:email`, `:password`

  Options:

    * `required` - true as default
    * `label` - If this isn't supplied, Brando will look for a Linguist
      `locale` in the form's `:model` property with the field name as key.
    * `slug_from` - :name
      Automatically slugs with `:name` as source.
    * `help_text` - "Help text for field". If not supplied, Brando will
      look at the form's `:model` parameters supplied with
      the form for Linguist translation. Set it in the model's
      meta with key `help`.
    * `placeholder` - "Placeholder for field"
    * `tags` - true. If true, binds tags javascript listener to field
      which splits tags by comma.
    * `confirm` - true. Inserts a confirmation field. You would then add
      `validate_confirmation(:password, message: "No match")`
      to your models changeset functions.
    * `default` - Default value. Can also be a function like
      `&__MODULE__.default_func/0`

  `:textarea` - Standard textarea

  Options

    * `rows` - How many rows to display in the textarea.
    * `required` - true as default
    * `label` - "Label for field"
    * `help_text` - "Help text for field"
    * `placeholder` - "Placeholder for field"
    * `default` - Default value. Can also be a function like
      `&__MODULE__.default_func/0`

  `:checkbox` - Standard checkbox

  Options

    * `multiple` - Multiple checkboxes.
      Gets labels/values from `choices` option
    * `choices` - &__MODULE__.get_status_choices/0.
    * `is_selected` - Pass a function that checks if `value` is selected.
      The function gets passed the checkbox's value, and
      the model's value.
      &__MODULE__.status_is_selected/2
    * `label`: "Label for field"
    * `empty_value`: Value to set if none of the boxes are checked.
    * `default`: true/false. Set as a value when using `multiple`.
      - ex: "2"

  `:select` - Select with options through `choices`.

  Options

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

  `:file` - Attach a file to the form. Sets the form to multipart.

  Options

    * `label` - "Label for file field"

  `:radio` - A group of radio buttons through `choices`

  Options

    * `choices` - &__MODULE__.get_status_choices/0
    * `is_selected` - Pass a function that checks if `value` is selected.
      The function gets passed the checkbox's value, and
      the model's value.
      &__MODULE__.status_is_selected/2
    * `label` - Label for the entire group. Each individual radio
      gets its label from the `choices` function.
    * `label_class` - Label class for the main label.

  `:datetime` - A datetime field with javascript picker

  Options

    * `required` - true as default
    * `label` - "Label for field"
    * `help_text` - "Help text for field"
    * `placeholder` - "Placeholder for field"
    * `default` - Default value. Can also be a function like
      `&__MODULE__.default_func/0`

  """
  defmacro field(name, type, opts \\ []) do
    quote do
      Brando.Form.__field__(__MODULE__, unquote(name),
                            unquote(type), unquote(opts))
    end
  end

  @doc """
  Marks the field as a field of some `type`. See docs for `field/3` macro.
  """
  def __field__(module, name, type, opts) do
    check_type!(type)
    fields = Module.get_attribute(module, :form_fields)

    if Module.get_attribute(module, :in_fieldset) do
      opts = [in_fieldset: Module.get_attribute(module, :in_fieldset)] ++ opts
    end

    clash = Enum.any?(fields, fn {prev, _} -> name == prev end)
    if clash do
      raise ArgumentError, message: "field `#{name}` was already set on schema"
    end

    Module.put_attribute(module, :form_fields, [{name, [type: type] ++ opts}|fields])

    if type == :file do
      form_opts =
        module
        |> Module.get_attribute(:form_opts)
        |> Map.put(:multipart, true)

      Module.put_attribute(module, :form_opts, form_opts)
    end
  end

  @doc """
  Defines a fieldset.

  ## Options

    * `legend`
      - Set to a string, or use `gettext("string")` for i18n.

  ## Example

      fieldset gettext("Header") do
        field :...
      end
  """
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
    fields = [{:"fs", [type: :fieldset] ++ [legend: legend]}|fields]
    Module.put_attribute(mod, :in_fieldset, true)
    Module.put_attribute(mod, :form_fields, fields)
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
    fields = Module.get_attribute(mod, :form_fields)
    fields = [{:"fs", [type: :fieldset_close]}|fields]
    Module.put_attribute(mod, :in_fieldset, nil)
    Module.put_attribute(mod, :form_fields, fields)
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
    name = opts[:name] || :submit
    fields = Module.get_attribute(mod, :form_fields)
    clash = Enum.any?(fields, fn {prev, _} -> name == prev end)
    if clash do
      raise ArgumentError,
            message: "submit field `#{name}` was already set on schema"
    end
    fields = [{name, [type: :submit, text: text] ++ opts}|fields]
    Module.put_attribute(mod, :form_fields, fields)
  end

  @doc """
  Evals the quoted action function, normally a path helper,
  and returns the result
  """
  def apply_action(fun, action, params \\ nil)
  def apply_action(fun, action, params) when is_list(params) do
    apply(Brando.helpers, fun, [Brando.endpoint(), action] ++ params)
  end
  def apply_action(fun, action, nil) do
    apply(Brando.helpers, fun, [Brando.endpoint(), action])
  end
  def apply_action(fun, action, params) do
    apply(Brando.helpers, fun, [Brando.endpoint(), action, params])
  end

  defp check_type!(type)
  when type in @valid_field_types do
    :ok
  end

  defp check_type!(type) do
    raise ArgumentError,
          message: "`#{Macro.to_string(type)}` is not a valid field type"
  end

  defp get_method(action)
  defp get_method(:create), do: "post"
  defp get_method(:update), do: "patch"
  defp get_method(:delete), do: "delete"
  defp get_method(_), do: "get"

  defp get_value(nil, _), do: nil
  defp get_value(%{data: data, action: nil, params: %{}}, name) do
    do_get_value(data || %{}, name)
  end
  defp get_value(%{data: _, action: nil, params: params}, name) do
    do_get_value(params, Atom.to_string(name))
  end
  defp get_value(%{data: _, action: _, params: params}, name) do
    do_get_value(params || %{}, Atom.to_string(name))
  end

  defp do_get_value(fetch_from, name) do
    case Map.fetch(fetch_from, name) do
      {:ok, val} -> if is_integer(val), do: to_string(val), else: val
      :error     -> nil
    end
  end

  defp get_errors([], _), do: nil
  defp get_errors(%{action: nil}, _) do
    nil
  end
  defp get_errors(changeset, name) do
    case Keyword.get_values(changeset.errors, name) do
      []     -> nil
      nil    -> nil
      values -> values
    end
  end
end
