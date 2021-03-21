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
          def to_iodata(%{html: html}) do
            html
            |> Phoenix.HTML.raw()
            |> Phoenix.HTML.Safe.to_iodata()
          end

          def to_iodata(entry) do
            raise """

            Failed to auto generate protocol for #{inspect(__MODULE__)} struct.
            Missing `:html` key.

            Call `use Brando.Villain.Schema, generate_protocol: false` instead

            """
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
  def generate_html(changeset, data_field \\ :data)

  def generate_html(%Ecto.Changeset{valid?: true} = changeset, data_field) do
    html_field =
      data_field
      |> to_string()
      |> String.replace("data", "html")
      |> String.to_atom()

    if Ecto.Changeset.get_change(changeset, data_field) do
      applied_changes = Ecto.Changeset.apply_changes(changeset)
      data_src = Map.get(applied_changes, data_field)

      parsed_data =
        Brando.Villain.parse(data_src, applied_changes,
          data_field: data_field,
          html_field: html_field
        )

      Ecto.Changeset.put_change(changeset, html_field, parsed_data)
    else
      changeset
    end
  end

  def generate_html(changeset, _) do
    changeset
  end
end
