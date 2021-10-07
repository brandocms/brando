defmodule Brando.Blueprint.Form do
  @moduledoc """
  # Form

  ## Input types

  ### `blocks`

  Block editor

  #### Options

      - `template_namespace`: Show templates from this namespace as starting
        points when presented with a blank editor

  """
  import Brando.Gettext

  defstruct name: :default,
            query: &__MODULE__.default_query/1,
            default_params: %{},
            tabs: [],
            redirect_on_save: nil

  defmacro forms(do: block) do
    forms(__CALLER__, block)
  end

  defp forms(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :forms, accumulate: true)
      Module.put_attribute(__MODULE__, :brando_macro_context, :forms)
      unquote(block)
    end
  end

  @doc """

  ## Default params

  You can supply a `default_params` option if you want the form to be
  prepopulated with your own defaults when creating a new entry:

      form default_params: %{status: :draft} do
        # ...
      end

  ## Redirect after save

  By default, we will redirect to the List view of your blueprint. You
  can override this by using `redirect_on_save/1`
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

  defp form(_caller, name, opts, block) do
    default_params = Keyword.get(opts, :default_params, %{})

    quote generated: true, location: :keep do
      Module.put_attribute(__MODULE__, :brando_macro_context, :form)

      var!(b_tab) = []
      var!(b_fieldset) = []
      var!(b_subform) = []
      var!(b_form) = []
      var!(b_redirect_on_save) = nil
      var!(b_query) = &Brando.Blueprint.Form.default_query/1

      unquote(block)

      default_params = unquote(Macro.escape(default_params))

      named_form = %Brando.Blueprint.Form{
        name: unquote(name),
        tabs: Enum.reverse(var!(b_form)),
        default_params: default_params,
        redirect_on_save: var!(b_redirect_on_save),
        query: var!(b_query)
      }

      Module.put_attribute(__MODULE__, :forms, named_form)

      _ = var!(b_subform)
      _ = var!(b_fieldset)
      _ = var!(b_tab)
    end
  end

  @doc """
  Where to redirect after a successful save

  Accepts a 2-arity function as `target`. The function should return a path/url.

  ## Example

      form do
        redirect_on_save &__MODULE__.my_custom_redirect/2
      end

      def my_custom_redirect(socket, _entry) do
        Brando.routes().admin_live_path(socket, BrandoAdmin.PageListView)
      end
  """
  defmacro redirect_on_save(target) do
    do_redirect_on_save(target)
  end

  defp do_redirect_on_save(target) do
    quote location: :keep do
      unless @brando_macro_context == :form do
        raise Brando.Exception.BlueprintError,
          message: """
          `redirect_on_save/1` must be nested directly under a form. was: `#{inspect(@brando_macro_context)}`

          Example:

              form do
                redirect_on_save "/admin/dashboard"
              end
          """
      end

      unless is_function(unquote(target), 2) do
        raise Brando.Exception.BlueprintError,
          message: """
          `redirect_on_save/1` needs a 2-arity function as parameter

          Example:

              form do
                redirect_on_save &__MODULE__.my_custom_redirect/2
              end

              def my_custom_redirect(socket, entry) do
                # ...
              end
          """
      end

      var!(b_redirect_on_save) = unquote(target)
    end
  end

  @doc """
  Set your form's entry query

  Default query is `%{matches: %{id: id}}`, but if you for instance need some preloads:

      forms do
        form do
          form_query &__MODULE__.query_with_preloads/1
        end
      end

      def query_with_preloads(id) do
        %{matches: %{id: id}, preload: [:illustrators]}
      end

  """
  defmacro form_query(query_fun) do
    do_form_query(query_fun)
  end

  defp do_form_query(query_fun) do
    quote location: :keep do
      unless @brando_macro_context == :form do
        raise Brando.Exception.BlueprintError,
          message: """
          `form_query/1` must be nested directly under a form. was: `#{inspect(@brando_macro_context)}`

          Example:

              form do
                form_query &__MODULE__.form_query/1
              end
          """
      end

      unless is_function(unquote(query_fun), 1) do
        raise Brando.Exception.BlueprintError,
          message: """
          `form_query/1` needs a 1-arity function as parameter

          Example:

              form do
                form_query &__MODULE__.form_query/1
              end

              def form_query(id) do
                %{matches: %{id: id}, preload: [:clients]}
              end
          """
      end

      var!(b_query) = unquote(query_fun)
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

      prev_ctx = @brando_macro_context

      unless @brando_macro_context == :form do
        raise Brando.Exception.BlueprintError,
          message: """
          tab must be nested under a form -- #{inspect(@brando_macro_context)}
          """
      end

      Module.put_attribute(__MODULE__, :brando_macro_context, :tab)

      var!(b_tab) = []

      unquote(block)

      named_tab = build_tab(unquote(name), Enum.reverse(var!(b_tab)))
      var!(b_form) = List.wrap(named_tab) ++ var!(b_form)

      Module.put_attribute(__MODULE__, :brando_macro_context, prev_ctx)

      # reset fieldset(s) since tab is processed
      var!(b_fieldset) = []
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
      prev_ctx = @brando_macro_context

      unless @brando_macro_context == :tab do
        raise Brando.Exception.BlueprintError,
          message: """
          fieldset must be nested under a tab -- #{inspect(@brando_macro_context)}
          """
      end

      Module.put_attribute(__MODULE__, :brando_macro_context, :fieldset)

      var!(b_subform) = []
      var!(b_fieldset) = []

      unquote(block)

      named_fieldset = build_fieldset(unquote(opts), Enum.reverse(var!(b_fieldset)))
      var!(b_tab) = List.wrap(named_fieldset) ++ var!(b_tab)

      Module.put_attribute(__MODULE__, :brando_macro_context, prev_ctx)

      _ = var!(b_subform)
      _ = var!(b_fieldset)
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

      prev_ctx = @brando_macro_context

      unless @brando_macro_context == :fieldset do
        raise Brando.Exception.BlueprintError,
          message: """
          inputs_for must be nested under a fieldset -- #{inspect(@brando_macro_context)}
          """
      end

      Module.put_attribute(__MODULE__, :brando_macro_context, :subform)

      named_subform = build_subform(unquote(field), unquote(opts), unquote(component))
      var!(b_fieldset) = List.wrap(named_subform) ++ var!(b_fieldset)

      Module.put_attribute(__MODULE__, :brando_macro_context, prev_ctx)
    end
  end

  defp do_inputs_for(field, opts, block) do
    quote location: :keep do
      _ = var!(b_subform)
      _ = var!(b_fieldset)

      prev_ctx = @brando_macro_context

      unless @brando_macro_context == :fieldset do
        raise Brando.Exception.BlueprintError,
          message: """
          inputs_for must be nested under a fieldset -- #{inspect(@brando_macro_context)}
          """
      end

      Module.put_attribute(__MODULE__, :brando_macro_context, :subform)

      var!(b_subform) = []

      unquote(block)

      named_subform = build_subform(unquote(field), unquote(opts), Enum.reverse(var!(b_subform)))
      var!(b_fieldset) = List.wrap(named_subform) ++ var!(b_fieldset)

      Module.put_attribute(__MODULE__, :brando_macro_context, prev_ctx)
    end
  end

  defmacro input(do: tpl) do
    quote location: :keep do
      if @brando_macro_context == :tab do
        raise Brando.Exception.BlueprintError,
          message: """
          input must be nested under a subform or fieldset, not a tab -- #{inspect(@brando_macro_context)}
          """
      end

      {var!(b_subform), var!(b_fieldset)} =
        case @brando_macro_context do
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
      if @brando_macro_context == :tab do
        raise Brando.Exception.BlueprintError,
          message: """
          input must be nested under a subform or fieldset, not a tab -- #{inspect(@brando_macro_context)}
          """
      end

      {var!(b_subform), var!(b_fieldset)} =
        case @brando_macro_context do
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

  def default_query(id), do: %{matches: %{id: id}}

  defp find_field(inputs, field) do
    Enum.find(inputs, fn
      %{name: name} -> name == field
      %{field: subform_field} -> subform_field == field
    end)
  end
end
