defmodule Brando.Villain.Schema do
  @moduledoc """
  Interface to Villain HTML editor.

  # Schema

  Schema utilities

  ## Usage

      use Brando.Villain.Schema

  Add fields to your schema:

      schema "my_schema" do
        field :header, :string
        villain :biography
      end

  As Ecto 1.1 removed callbacks, we must manually call for HTML generation.
  In your schema's `changeset` functions:

      def changeset(schema, :create, params) do
        schema
        |> cast(params, @required_fields, @optional_fields)
        |> generate_html()
      end

  You can configure which parser to use with

      config :brando, Brando.Villain, :parser

  """
  defmacro __using__(opts) do
    quote do
      Module.register_attribute(__MODULE__, :villain_fields, accumulate: true)
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      unless Keyword.fetch(unquote(opts), :generate_protocol) == {:ok, false} do
        defimpl Phoenix.HTML.Safe, for: __MODULE__ do
          def to_iodata(entry) do
            entry.html
            |> Phoenix.HTML.raw()
            |> Phoenix.HTML.Safe.to_iodata()
          end
        end
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    villain_fields = Module.get_attribute(env.module, :villain_fields)
    compile(villain_fields)
  end

  @doc false
  def compile(villain_fields) do
    quote do
      def __villain_fields__ do
        {__MODULE__, unquote(Macro.escape(villain_fields))}
      end
    end
  end

  @doc """
  Macro for villain schema fields.
  """
  defmacro villain(field \\ nil) do
    data_field = (field && field |> to_string |> Kernel.<>("_data") |> String.to_atom()) || :data
    html_field = (field && field |> to_string |> Kernel.<>("_html") |> String.to_atom()) || :html

    quote do
      Module.put_attribute(
        __MODULE__,
        :villain_fields,
        {:villain, unquote(data_field), unquote(html_field)}
      )

      Ecto.Schema.field(unquote(data_field), {:array, :map})
      Ecto.Schema.field(unquote(html_field), :string)
    end
  end

  @doc """
  Takes the schema's `json` field and transforms to `html`.

  This is usually called from your schema's `changeset` functions:

      def changeset(schema, :create, params) do
        schema
        |> cast(params, @required_fields, @optional_fields)
        |> generate_html()
      end
  """
  def generate_html(
        changeset,
        field \\ nil
      ) do
    data_field = (field && field |> to_string |> Kernel.<>("_data") |> String.to_atom()) || :data
    html_field = (field && field |> to_string |> Kernel.<>("_html") |> String.to_atom()) || :html

    if Ecto.Changeset.get_change(changeset, data_field) do
      data_src = Map.get(changeset.changes, data_field)
      parsed_data = Brando.Villain.parse(data_src, changeset.data)
      Ecto.Changeset.put_change(changeset, html_field, parsed_data)
    else
      changeset
    end
  end
end
