defmodule Brando.Blueprint.Form do
  @moduledoc """
  ### Form
  """
  import Brando.Gettext

  defstruct name: :default,
            default_params: %{},
            tabs: []

  defmacro forms(do: block) do
    forms(__CALLER__, block)
  end

  defp forms(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :forms, accumulate: true)
      var!(b_form_ctx) = :forms
      unquote(block)
      _ = var!(b_form_ctx)
    end
  end

  @doc """

  ## Default params

  You can supply a `default_params` option if you want the form to be
  prepopulated with your own defaults when creating a new entry:

      form default_params: %{status: :draft} do
        # ...
      end

  """
  defmacro form(name, opts, do: block) when is_list(opts) do
    form(__CALLER__, name, opts, block)
  end

  defmacro form(opts, do: block) when is_list(opts) do
    form(__CALLER__, :default, opts, block)
  end

  defmacro form(name, do: block) do
    form(__CALLER__, name, [], block)
  end

  defmacro form(do: block) do
    form(__CALLER__, :default, [], block)
  end

  defp form(caller, name, opts, block) do
    default_params = Keyword.get(opts, :default_params, %{})

    quote generated: true, location: :keep do
      var!(b_fieldset) = []
      var!(b_subform) = []
      var!(b_tab) = []
      var!(b_form) = []
      var!(b_form_ctx) = :form

      unquote(block)

      default_params = unquote(Macro.escape(default_params))

      named_form = %Brando.Blueprint.Form{
        name: unquote(name),
        tabs: Enum.reverse(var!(b_form)),
        default_params: default_params
      }

      Module.put_attribute(__MODULE__, :forms, named_form)

      _ = var!(b_subform)
      _ = var!(b_fieldset)
      _ = var!(b_tab)
      _ = var!(b_form_ctx)
    end
  end

  defmacro tab(do: block) do
    do_tab(gettext("Content"), block)
  end

  defmacro tab(name, do: block) do
    do_tab(name, block)
  end

  defp do_tab(name, block) do
    quote location: :keep do
      _ = var!(b_subform)
      _ = var!(b_fieldset)
      _ = var!(b_tab)

      prev_ctx = var!(b_form_ctx)

      unless prev_ctx == :form do
        raise Brando.Exception.BlueprintError,
          message: """
          tab must be nested under a form -- #{inspect(prev_ctx)}
          """
      end

      var!(b_form_ctx) = :tab
      var!(b_tab) = []

      unquote(block)
      named_tab = build_tab(unquote(name), Enum.reverse(var!(b_tab)))
      var!(b_form) = List.wrap(named_tab) ++ var!(b_form)

      # reset fieldset(s) since tab is processed
      var!(b_fieldset) = []
      var!(b_form_ctx) = prev_ctx
      _ = var!(b_form_ctx)
    end
  end

  defmacro fieldset(do: block) do
    do_fieldset([], block)
  end

  defmacro fieldset(opts, do: block) do
    do_fieldset(opts, block)
  end

  defp do_fieldset(opts, block) do
    quote location: :keep do
      prev_ctx = var!(b_form_ctx)

      unless prev_ctx == :tab do
        raise Brando.Exception.BlueprintError,
          message: """
          fieldset must be nested under a tab -- #{inspect(prev_ctx)}
          """
      end

      var!(b_form_ctx) = :fieldset
      var!(b_subform) = []
      var!(b_fieldset) = []

      unquote(block)

      named_fieldset = build_fieldset(unquote(opts), Enum.reverse(var!(b_fieldset)))
      var!(b_tab) = List.wrap(named_fieldset) ++ var!(b_tab)

      var!(b_form_ctx) = prev_ctx

      _ = var!(b_subform)
      _ = var!(b_fieldset)
      _ = var!(b_form_ctx)
    end
  end

  defmacro inputs_for(field, {:component, component}) do
    do_inputs_for(field, component, [])
  end

  defmacro inputs_for(field, do: block) do
    do_inputs_for(field, [], block)
  end

  defmacro inputs_for(field, {:component, component}, opts) do
    do_inputs_for(field, component, opts)
  end

  defmacro inputs_for(field, opts, do: block) do
    do_inputs_for(field, opts, block)
  end

  defp do_inputs_for(field, component, opts) when is_atom(component) do
    quote location: :keep do
      _ = var!(b_subform)
      _ = var!(b_fieldset)

      prev_ctx = var!(b_form_ctx)

      unless prev_ctx == :fieldset do
        raise Brando.Exception.BlueprintError,
          message: """
          inputs_for must be nested under a fieldset -- #{inspect(prev_ctx)}
          """
      end

      named_subform = build_subform(unquote(field), unquote(opts), unquote(component))
      var!(b_fieldset) = List.wrap(named_subform) ++ var!(b_fieldset)
    end
  end

  defp do_inputs_for(field, opts, block) do
    quote location: :keep do
      _ = var!(b_subform)
      _ = var!(b_fieldset)

      prev_ctx = var!(b_form_ctx)

      unless prev_ctx == :fieldset do
        raise Brando.Exception.BlueprintError,
          message: """
          inputs_for must be nested under a fieldset -- #{inspect(prev_ctx)}
          """
      end

      var!(b_form_ctx) = :subform
      var!(b_subform) = []
      _ = var!(b_form_ctx)

      unquote(block)

      named_subform = build_subform(unquote(field), unquote(opts), Enum.reverse(var!(b_subform)))
      var!(b_fieldset) = List.wrap(named_subform) ++ var!(b_fieldset)
      var!(b_form_ctx) = prev_ctx
      _ = var!(b_form_ctx)
    end
  end

  defmacro input(do: tpl) do
    quote location: :keep do
      if var!(b_form_ctx) == :tab do
        raise Brando.Exception.BlueprintError,
          message: """
          input must be nested under a subform or fieldset, not a tab -- #{inspect(var!(b_form_ctx))}
          """
      end

      {var!(b_subform), var!(b_fieldset)} =
        case var!(b_form_ctx) do
          :subform ->
            {
              List.wrap(build_input(unquote(tpl), :surface)) ++ var!(b_subform),
              var!(b_fieldset)
            }

          _ ->
            {
              var!(b_subform),
              List.wrap(build_input(unquote(tpl), :surface)) ++ var!(b_fieldset)
            }
        end
    end
  end

  defmacro input(name, type, opts \\ []) do
    quote location: :keep,
          bind_quoted: [name: name, type: type, opts: opts] do
      if var!(b_form_ctx) == :tab do
        raise Brando.Exception.BlueprintError,
          message: """
          input must be nested under a subform or fieldset, not a tab -- #{inspect(var!(b_form_ctx))}
          """
      end

      {var!(b_subform), var!(b_fieldset)} =
        case var!(b_form_ctx) do
          :subform ->
            {
              List.wrap(build_input(name, type, opts)) ++ var!(b_subform),
              var!(b_fieldset)
            }

          _ ->
            {
              var!(b_subform),
              List.wrap(build_input(name, type, opts)) ++ var!(b_fieldset)
            }
        end
    end
  end

  def build_tab(name, fields) do
    %__MODULE__.Tab{name: name, fields: fields}
  end

  def build_subform(field, component, opts) when is_atom(component) do
    mapped_opts = Enum.into(opts, %{})
    Map.merge(%__MODULE__.Subform{field: field, component: component}, mapped_opts)
  end

  def build_subform(field, opts, sub_fields) when is_list(opts) do
    mapped_opts = Enum.into(opts, %{})
    Map.merge(%__MODULE__.Subform{field: field, sub_fields: sub_fields}, mapped_opts)
  end

  def build_fieldset(opts, fields) do
    mapped_opts = Enum.into(opts, %{})

    Map.merge(
      %__MODULE__.Fieldset{
        fields: fields
      },
      mapped_opts
    )
  end

  def build_input(tpl, type) do
    %__MODULE__.Input{
      template: tpl,
      type: type,
      opts: []
    }
  end

  def build_input(name, type, opts) do
    %__MODULE__.Input{
      name: name,
      type: type,
      opts: opts
    }
  end

  def get_tab_for_field(field, %__MODULE__{tabs: tabs}) do
    for tab <- tabs,
        %__MODULE__.Fieldset{fields: inputs} <- tab.fields do
      find_field(inputs, field) && tab.name
    end
    |> Enum.filter(&is_binary(&1))
    |> List.first()
  end

  defp find_field(inputs, field) do
    Enum.find(inputs, fn
      %{name: name} -> name == field
      %{field: subform_field} -> subform_field == field
    end)
  end
end
