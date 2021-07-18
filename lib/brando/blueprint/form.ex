defmodule Brando.Blueprint.Form do
  @moduledoc """
  ### Form
  """
  defmodule Subform do
    defstruct field: nil,
              cardinality: :one,
              sub_fields: [],
              style: :regular,
              default: nil
  end

  defmodule Fieldset do
    defstruct size: :full,
              style: :regular,
              fields: []
  end

  defmodule Input do
    defstruct name: nil,
              type: nil,
              opts: %{}
  end

  defmacro form(do: block) do
    form(__CALLER__, block)
  end

  defp form(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :form, accumulate: true)

      var!(b_fieldset) = []
      var!(b_subform) = []
      var!(b_form_ctx) = :fieldset

      unquote(block)

      _ = var!(b_subform)
      _ = var!(b_fieldset)
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
      var!(b_form_ctx) = :fieldset
      var!(b_fieldset) = []
      var!(b_subform) = []

      unquote(block)
      named_fieldset = build_fieldset(unquote(opts), Enum.reverse(var!(b_fieldset)))
      Module.put_attribute(__MODULE__, :form, named_fieldset)

      _ = var!(b_subform)
      _ = var!(b_fieldset)
      _ = var!(b_form_ctx)
    end
  end

  defmacro inputs_for(field, do: block) do
    do_inputs_for(field, [], block)
  end

  defmacro inputs_for(field, opts, do: block) do
    do_inputs_for(field, opts, block)
  end

  defp do_inputs_for(field, opts, block) do
    quote location: :keep do
      _ = var!(b_subform)
      _ = var!(b_fieldset)
      _ = var!(b_form_ctx)

      var!(b_form_ctx) = :subform
      var!(b_subform) = []
      unquote(block)
      named_subform = build_subform(unquote(field), unquote(opts), Enum.reverse(var!(b_subform)))
      var!(b_fieldset) = List.wrap(named_subform) ++ var!(b_fieldset)
      var!(b_form_ctx) = :fieldset
    end
  end

  defmacro input(name, type, opts \\ []) do
    quote location: :keep,
          bind_quoted: [name: name, type: type, opts: opts] do
      {var!(b_subform), var!(b_fieldset)} =
        if var!(b_form_ctx) == :subform do
          {List.wrap(build_input(name, type, opts)) ++ var!(b_subform), var!(b_fieldset)}
        else
          {var!(b_subform), List.wrap(build_input(name, type, opts)) ++ var!(b_fieldset)}
        end

      # _ = var!(b_subform)
    end
  end

  def build_subform(field, opts, sub_fields) do
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

  def build_input(name, type, opts) do
    %__MODULE__.Input{
      name: name,
      type: type,
      opts: opts
    }
  end
end
