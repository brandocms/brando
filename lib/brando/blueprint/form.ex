defmodule Brando.Blueprint.Form do
  @moduledoc """
  ### Form
  """
  defmodule Subform do
    defstruct size: :full,
              field: nil,
              cardinality: :one,
              sub_fields: [],
              style: :regular,
              default: nil
  end

  defmodule Fieldset do
    defstruct size: :full,
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
      unquote(block)
    end
  end

  defmacro fieldset(size, do: block) do
    do_fieldset(size, block)
  end

  defmacro fieldset(do: block) do
    do_fieldset(:full, block)
  end

  defp do_fieldset(size, block) do
    quote location: :keep do
      var!(fs) = []
      unquote(block)
      named_fieldset = build_fieldset(unquote(size), Enum.reverse(var!(fs)))
      Module.put_attribute(__MODULE__, :form, named_fieldset)
    end
  end

  defmacro subform(field, opts, do: block) do
    do_subform(field, opts, block)
  end

  defp do_subform(field, opts, block) do
    size = Keyword.get(opts, :size, :full)

    quote location: :keep do
      var!(fs) = []
      unquote(block)
      named_subform = build_subform(unquote(field), unquote(size), Enum.reverse(var!(fs)))
      Module.put_attribute(__MODULE__, :form, named_subform)
    end
  end

  defmacro subform_many(field, opts, do: block) do
    do_subform_many(field, opts, block)
  end

  defp do_subform_many(field, opts, block) do
    size = Keyword.get(opts, :size, :full)
    default = Keyword.get(opts, :default, nil)
    style = Keyword.get(opts, :style, nil)

    quote location: :keep do
      var!(fs) = []
      unquote(block)

      named_subform =
        build_subform(
          unquote(field),
          unquote(size),
          Enum.reverse(var!(fs)),
          :many,
          unquote(default),
          unquote(style)
        )

      Module.put_attribute(__MODULE__, :form, named_subform)
    end
  end

  defmacro input(name, type, opts \\ []) do
    quote location: :keep,
          bind_quoted: [name: name, type: type, opts: opts] do
      var!(fs) = List.wrap(build_input(name, type, opts)) ++ var!(fs)
    end
  end

  def build_subform(
        field,
        size,
        sub_fields,
        cardinality \\ :one,
        default \\ nil,
        style \\ :regular
      ) do
    %__MODULE__.Subform{
      size: size,
      field: field,
      sub_fields: sub_fields,
      cardinality: cardinality,
      default: default,
      style: style
    }
  end

  def build_fieldset(size, fields) do
    %__MODULE__.Fieldset{
      size: size,
      fields: fields
    }
  end

  def build_input(name, type, opts) do
    %__MODULE__.Input{
      name: name,
      type: type,
      opts: opts
    }
  end
end
