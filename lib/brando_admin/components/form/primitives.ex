defmodule BrandoAdmin.Components.Form.Primitives do
  @moduledoc """
  The form's input primitives: `field_base/1`, `input/1`, the `inputs_for_*`
  and `array_inputs*` wrappers, `label/1`, `error_tag/1` and `submit_button/1`.

  ## Why these are not in `BrandoAdmin.Components.Form`

  They were, and it made `Form` the sink of a compile cycle. 27 modules call
  them — `field_base/1` alone has ~90 call sites — while `Form` itself used only
  two of them. So every input, drawer and block component depended on the
  6200-line module, and `Form` depended back on those components to render them.
  `mix xref` reported the whole admin form tree as one 202-node cycle.

  Phase 9C moved the video drawer's markup out on the same reasoning and did
  *not* achieve this: a leaf that nothing depends on can move without changing
  the graph. Direction is what matters. These are the functions the tree depends
  **on**, so moving them is what actually cuts the edge.

  ## What belongs here

  Rendering primitives with no knowledge of the entry, the changeset lifecycle,
  or the form's drawers — they take a `Phoenix.HTML.FormField` and render it.
  Anything that reads or writes `Form`'s socket assigns belongs in `Form`.

  That test is why this module is deliberately not called `Chrome`, which is
  what the audit plan called the extraction it expected here: "chrome" describes
  a shell around content, and these are the innermost pieces rather than the
  outermost. The plan's line range for it (`:5274-6257`, "~35 pure function
  components") described neither this block nor anything else in the file — it
  predated two earlier extractions and was never re-measured.
  """
  use BrandoAdmin, :component
  use BrandoAdmin.Translator

  use Gettext, backend: Brando.Gettext

  import Phoenix.LiveView.TagEngine

  # Load-bearing beyond readability: `input/1` resolves an input type to its
  # component with `Module.concat([Input, type_module])`. Without this alias
  # `Input` is the bare atom `Elixir.Input`, so every lookup misses, silently
  # falls through to the function-component branch, and every select, textarea
  # and toggle in the admin raises `undefined function` at *render* time.
  #
  # The compiler cannot see this — `Module.concat/1` is runtime and a bare alias
  # is valid syntax — so nothing caught it until the mounted-LiveView tests ran.
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Utils

  attr :field, Phoenix.HTML.FormField
  attr :relation, :boolean
  attr :compact, :boolean, default: false
  attr :left_justify_meta, :boolean, default: false
  attr :meta_top, :boolean, default: false
  attr :instructions, :string
  attr :label, :any
  attr :class, :any
  attr :fit_content, :boolean, default: false
  attr :uid, :string
  attr :id_prefix, :string
  attr :skip_presence, :boolean, default: false
  slot :meta
  slot :header

  def field_base(assigns) do
    relation = Map.get(assigns, :relation, false)
    failed = has_error(assigns.field, relation)
    label = get_label(assigns)
    hidden = label == :hidden

    assigns =
      assigns
      |> assign_new(:uid, fn -> nil end)
      |> assign_new(:id_prefix, fn -> "" end)
      |> assign_new(:class, fn -> nil end)
      |> assign_new(:left_justify_meta, fn -> nil end)
      |> assign(:relation, relation)
      |> assign(:failed, failed)
      |> assign(:hidden, hidden)
      |> assign(:label, label)
      |> assign(:raw_instructions, assigns[:instructions])

    assigns =
      assigns
      |> assign(:f_id, field_id(assigns))
      |> assign(:f_name, assigns[:field] && assigns[:field].name)

    ~H"""
    <div
      class={["field-wrapper", @class, @fit_content && "fit-content"]}
      id={"#{@f_id}-field-wrapper"}
      phx-hook="Brando.FieldBase"
    >
      <div class={["label-wrapper", @hidden && "hidden"]}>
        <label
          for={"#{@f_id}"}
          class={["control-label", @failed && "failed"]}
          data-field-presence={!@skip_presence && @f_name}
        >
          <span>{@label}</span>
          <div
            :if={!@skip_presence}
            class="field-presence"
            phx-update="ignore"
            id={"#{@f_id}-field-presence"}
          >
          </div>
        </label>
        <.error_tag
          :if={@field}
          field={@field}
          relation={@relation}
          id_prefix={@id_prefix}
          uid={@uid}
        />
        <div :if={@header != []} class="field-wrapper-header">
          {render_slot(@header)}
        </div>
      </div>
      <%= if @raw_instructions || @meta do %>
        <div :if={@meta_top} class={["meta", @left_justify_meta && "left"]}>
          <%= if @raw_instructions do %>
            <div class="help-text">
              ↳ <span>{@raw_instructions}</span>
            </div>
            <div :if={@meta != []} class="extra">
              {render_slot(@meta)}
            </div>
          <% end %>
        </div>
      <% end %>
      <div class="field-base" id={"#{@f_id}-field-base"}>
        {render_slot(@inner_block)}
      </div>
      <%= if @raw_instructions || @meta do %>
        <div :if={!@meta_top} class={["meta", @left_justify_meta && "left"]}>
          <%= if @raw_instructions do %>
            <div class="help-text">
              ↳ <span>{@raw_instructions}</span>
            </div>
            <div :if={@meta != []} class="extra">
              {render_slot(@meta)}
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp get_label(%{label: nil} = assigns) do
    assigns.field.field
    |> to_string()
    |> Brando.Utils.humanize()
  end

  defp get_label(%{label: label}) do
    label
  end

  defp has_error(field, true) do
    # Gate on used_input? exactly as error_tag/1 does. Reading form.errors
    # directly flagged asset labels the moment the form rendered — red dots on a
    # blank create form, with no message to explain them, while a plain required
    # field alongside stayed quiet.
    relation_field = field.form[:"#{field.field}_id"]

    Phoenix.Component.used_input?(relation_field) and relation_field.errors != []
  end

  defp has_error(%{errors: []}, _), do: false
  defp has_error(%{errors: _}, _), do: true

  def input(assigns) do
    assigns =
      assigns
      |> assign_new(:path, fn -> [] end)
      |> assign_new(:component_id, fn -> assigns.field.id end)
      |> assign_new(:parent_form, fn -> nil end)
      |> assign_new(:parent_form_id, fn -> nil end)
      |> assign_new(:subform_id, fn -> nil end)
      |> assign_new(:form_id, fn -> nil end)
      |> assign_new(:compact, fn -> Keyword.get(assigns.opts, :compact, false) end)
      |> assign_new(:size, fn -> Keyword.get(assigns.opts, :size, "full") end)
      |> assign_new(:component_target, fn ->
        case assigns.type do
          {:component, _module} ->
            raise """

            {:component, module} is deprecated. Use {:live_component, module} instead.
            If you want to pass a function component, pass it as a function capture instead:

            &Components.my_component/1

            """

          {:live_component, module} ->
            module

          fun when is_function(fun, 1) ->
            fun

          type ->
            type_module = type |> to_string() |> Macro.camelize()
            input_module = Module.concat([Input, type_module])

            # if module exists, it's a live component. if not, function component
            case Code.ensure_compiled(input_module) do
              {:module, _} -> input_module
              _ -> Function.capture(BrandoAdmin.Components.Form.Input, type, 1)
            end
        end
      end)

    ~H"""
    <%= if is_function(@component_target) do %>
      <div class="brando-input" data-component={@type} data-compact={@compact} data-size={@size}>
        {component(
          @component_target,
          assigns,
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        )}
      </div>
    <% else %>
      <div
        class="brando-input"
        data-component={inspect(@type)}
        data-compact={@compact}
        data-size={@size}
      >
        <.live_component
          module={@component_target}
          id={@component_id}
          parent_form={@parent_form}
          parent_form_id={@parent_form_id}
          subform_id={@subform_id}
          field={@field}
          label={@label}
          path={@path}
          placeholder={@placeholder}
          instructions={@instructions}
          opts={@opts}
          current_user={@current_user}
          form_id={@form_id}
          on_change={
            if @form_id,
              do: fn params ->
                # `BrandoAdmin.Components.Form`, spelled out. This was
                # `__MODULE__` while it lived in that module — the one line in
                # this block whose meaning depended on where it sat, and the
                # compiler caught it because `Primitives` is a plain component
                # with no `send_update/2` to bind to. Left explicit rather than
                # re-aliased: the target is the *live component* that owns the
                # form's state, which is the thing this module deliberately
                # does not.
                Phoenix.LiveView.send_update(
                  BrandoAdmin.Components.Form,
                  Map.put(params, :id, @form_id)
                )
              end
          }
        />
      </div>
    <% end %>
    """
  end

  attr :field, Phoenix.HTML.FormField
  slot :inner_block

  def map_inputs(assigns) do
    subform = Utils.form_for_map(assigns.field)

    input_value =
      if input_value = assigns.field.value do
        Enum.reduce(input_value, %{}, fn
          {"_unused_" <> _k, _v}, acc -> acc
          {k, v}, acc -> Map.put(acc, k, v)
        end)
      end

    assigns =
      assigns
      |> assign(:subform, subform)
      |> assign(:input_value, input_value)

    ~H"""
    <%= if @input_value do %>
      <%= for {map_key, map_value} <- @input_value do %>
        {render_slot(@inner_block, %{
          name: "#{@field.name}[#{map_key}]",
          key: map_key,
          value: map_value,
          subform: @subform
        })}
      <% end %>
    <% end %>
    """
  end

  attr :field, Phoenix.HTML.FormField

  def map_value_inputs(assigns) do
    subform = Utils.form_for_map_value(assigns.field)
    input_value = assigns.field.value

    assigns =
      assigns
      |> assign(:subform, subform)
      |> assign(:input_value, input_value)

    ~H"""
    <%= for {map_key, map_value} <- @input_value do %>
      {render_slot(@inner_block, %{
        name: "#{@field.name}[#{map_key}]",
        key: map_key,
        value: map_value,
        subform: @subform
      })}
    <% end %>
    """
  end

  @doc type: :component
  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "A %Phoenix.HTML.Form{}/field name tuple, for example: {@form[:email]}."

  attr :id, :string,
    doc: """
    The id to be used in the form, defaults to the concatenation of the given
    field to the parent form id.
    """

  attr :as, :atom,
    doc: """
    The name to be used in the form, defaults to the concatenation of the given
    field to the parent form name.
    """

  attr :default, :any, doc: "The value to use if none is available."

  attr :prepend, :list,
    doc: """
    The values to prepend when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :append, :list,
    doc: """
    The values to append when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :skip_hidden, :boolean,
    default: false,
    doc: """
    Skip the automatic rendering of hidden fields to allow for more tight control
    over the generated markup.
    """

  slot :inner_block, required: true, doc: "The content rendered for each nested form."

  def inputs_for_block(assigns) do
    %Phoenix.HTML.FormField{form: form} = assigns.field
    options = assigns |> Map.take([:id, :as, :default, :append, :prepend]) |> Keyword.new()

    options =
      form.options
      |> Keyword.take([:multipart])
      |> Keyword.merge(options)

    forms =
      BrandoAdmin.Components.Form.Input.Blocks.Utils.to_form_single(
        form.source,
        assigns.field,
        options
      )

    assigns = assign(assigns, :forms, forms)

    ~H"""
    <%= for finner <- @forms do %>
      <%= unless @skip_hidden do %>
        <%= for {name, value_or_values} <- finner.hidden,
                name = name_for_value_or_values(finner, name, value_or_values),
                value <- List.wrap(value_or_values) do %>
          <input type="hidden" name={name} value={value} />
        <% end %>
      <% end %>
      {render_slot(@inner_block, finner)}
    <% end %>
    """
  end

  @doc type: :component
  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "A %Phoenix.HTML.Form{}/field name tuple, for example: {@form[:email]}."

  attr :id, :string,
    doc: """
    The id to be used in the form, defaults to the concatenation of the given
    field to the parent form id.
    """

  attr :as, :atom,
    doc: """
    The name to be used in the form, defaults to the concatenation of the given
    field to the parent form name.
    """

  attr :default, :any, doc: "The value to use if none is available."

  attr :prepend, :list,
    doc: """
    The values to prepend when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :append, :list,
    doc: """
    The values to append when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :skip_hidden, :boolean,
    default: false,
    doc: """
    Skip the automatic rendering of hidden fields to allow for more tight control
    over the generated markup.
    """

  slot :inner_block, required: true, doc: "The content rendered for each nested form."

  def inputs_for_poly(assigns) do
    %Phoenix.HTML.FormField{form: form} = assigns.field
    options = assigns |> Map.take([:id, :as, :default, :append, :prepend]) |> Keyword.new()

    options =
      form.options
      |> Keyword.take([:multipart])
      |> Keyword.merge(options)

    forms =
      BrandoAdmin.Components.Form.Input.Blocks.Utils.to_form_multi(
        form.source,
        assigns.field,
        options
      )

    assigns = assign(assigns, :forms, forms)

    ~H"""
    <%= for finner <- @forms do %>
      <%= unless @skip_hidden do %>
        <%= for {name, value_or_values} <- finner.hidden,
                name = name_for_value_or_values(finner, name, value_or_values),
                value <- List.wrap(value_or_values) do %>
          <input type="hidden" name={name} value={value} />
        <% end %>
      <% end %>
      {render_slot(@inner_block, finner)}
    <% end %>
    """
  end

  defp name_for_value_or_values(form, field, values) when is_list(values) do
    Phoenix.HTML.Form.input_name(form, field) <> "[]"
  end

  defp name_for_value_or_values(form, field, _value) do
    Phoenix.HTML.Form.input_name(form, field)
  end

  attr :field, Phoenix.HTML.FormField
  slot :inner_block

  def array_inputs(assigns) do
    assigns =
      assigns
      |> assign(:input_value, assigns.field.value)
      |> assign(:indexed_inputs, Enum.with_index(assigns.field.value || []))

    ~H"""
    <%= if @input_value do %>
      <%= for {array_value, array_index} <- @indexed_inputs do %>
        {render_slot(@inner_block, %{
          name: "#{@field.name}[]",
          index: array_index,
          value: array_value
        })}
      <% end %>
    <% end %>
    """
  end

  attr :field, Phoenix.HTML.FormField
  attr :options, :any
  slot :inner_block

  def array_inputs_from_data(assigns) do
    checked_values = assigns.field.value || []

    assigns =
      assigns
      |> assign(:checked_values, Enum.map(checked_values, &to_string(&1)))
      |> assign(:indexed_options, Enum.with_index(assigns.options))

    ~H"""
    <%= for {option, idx} <- @indexed_options do %>
      {render_slot(@inner_block, %{
        name: "#{@field.name}[]",
        id: "#{@field.id}-#{idx}",
        index: idx,
        value: option.value,
        label: option.label,
        checked: option.value in @checked_values
      })}
    <% end %>
    """
  end

  def submit_button(assigns) do
    ~H"""
    <button
      id={"#{@form_id}-submit"}
      type="button"
      disabled={@processing}
      data-processing={@processing}
      data-form-id={@form_id}
      data-testid="submit"
      class={@class}
      phx-hook="Brando.Submit"
    >
      <%= if @processing do %>
        <div class="processing">
          <svg
            class="spin"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            width="24"
            height="24"
          >
            <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
          </svg>
          {gettext("Processing. Please wait...")}
        </div>
      <% else %>
        {@label}
      <% end %>
    </button>
    """
  end

  defp field_id(%{uid: uid} = assigns) when not is_nil(uid) do
    "f-#{uid}-#{assigns[:id_prefix]}-#{assigns.field.id}"
  end

  defp field_id(assigns), do: "#{assigns.field.id}"

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate "is invalid" in the "errors" domain
    #     dgettext("errors", "is invalid")
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    # This requires us to call the Gettext module passing our gettext
    # backend as first argument.
    #
    # Note we use the "errors" domain, which means translations
    # should be written to the errors.po file. The :count option is
    # set by Ecto and indicates we should also apply plural rules.
    if count = opts[:count] do
      Gettext.dngettext(Brando.web_module(Gettext), "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Brando.web_module(Gettext), "errors", msg, opts)
    end
  end

  attr :field, Phoenix.HTML.FormField
  attr :relation, :atom
  attr :id_prefix, :string
  attr :uid, :string

  def error_tag(assigns) do
    # A relation/asset field is two things in the form: the association, and the
    # `<field>_id` hidden input that actually carries a value. `used_input?`
    # only ever returns true for the latter, so reading errors off the
    # association alone silently drops every message an asset field produces.
    # Collect from both and let whichever was used supply them.
    errors =
      [assigns.field | relation_field(assigns)]
      |> Enum.filter(&Phoenix.Component.used_input?/1)
      |> Enum.flat_map(& &1.errors)
      |> Enum.uniq()
      |> Enum.map(&label_group_fields(&1, assigns.field))

    assigns =
      assigns
      |> assign(:errors, errors)
      |> assign_new(:translate_fn, fn ->
        {mod, fun} = assigns[:translator] || {__MODULE__, :translate_error}
        &apply(mod, fun, [&1])
      end)

    assigns =
      if assigns.relation do
        relation_field_atom = :"#{assigns.field.field}_id"
        assign(assigns, :field, assigns.field.form[relation_field_atom])
      else
        assigns
      end

    assigns = assign(assigns, :f_id, field_id(assigns))

    ~H"""
    <span :for={error <- @errors} id={"#{@f_id}-error"} class="field-error">
      {@translate_fn.(error)}
    </span>
    """
  end

  defp relation_field(%{relation: true, field: field}), do: [field.form[:"#{field.field}_id"]]
  defp relation_field(_assigns), do: []

  # Group constraints (`one_of`, `exactly_one_of`) name the other fields in the
  # set. The changeset only knows them as atoms; here we have the schema, and so
  # the labels the editor actually sees on those inputs.
  defp label_group_fields({msg, opts} = error, field) do
    case opts[:one_of] || opts[:exactly_one_of] do
      nil -> error
      fields -> {msg, Keyword.put(opts, :fields, field_labels(fields, field))}
    end
  end

  defp field_labels(fields, field) do
    schema = field.form.data.__struct__

    fields
    |> Brando.Blueprint.Utils.translate_error_keys(schema.__form__(), schema)
    |> Enum.join(", ")
  rescue
    _error -> Enum.map_join(fields, ", ", &to_string/1)
  end

  attr :form, :any
  attr :field, :any
  attr :uid, :any, default: nil
  attr :id_prefix, :string, default: ""
  attr :class, :any, default: nil
  attr :click, :any, default: nil
  attr :popover, :string, default: nil
  attr :skip_presence, :boolean, default: false
  slot :inner_block

  def label(assigns) do
    assigns =
      assigns
      |> assign(:f_id, field_id(assigns))
      |> assign(:f_name, assigns[:field] && assigns[:field].name)

    ~H"""
    <label
      class={@class}
      for={@f_id}
      data-popover={@popover}
      phx-click={@click}
      data-field-presence={@f_name}
    >
      {render_slot(@inner_block)}
      <div
        :if={!@skip_presence}
        class="field-presence"
        phx-update="ignore"
        id={"#{@f_id}-field-presence"}
      >
      </div>
    </label>
    """
  end
end
