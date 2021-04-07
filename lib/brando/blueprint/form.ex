defmodule Brando.Blueprint.Form do
  @moduledoc """
  ### Form
  """

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

  defmacro input(name, type, opts \\ []) do
    quote location: :keep,
          bind_quoted: [name: name, type: type, opts: opts] do
      var!(fs) = List.wrap(build_input(name, type, opts)) ++ var!(fs)
    end
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
