defmodule Brando.Blueprint.Identifier.DSL do
  @moduledoc """
  DSL macros for defining identifiers in blueprints.

  ## Example

      identifier "{{ entry.title }}"

  ## Disabling identifiers

      identifier false

  ## Persistence control

      persist_identifier true   # Save to database (default)
      persist_identifier false  # Don't persist to database
  """

  alias Brando.Blueprint.Identifier.Template
  alias Brando.Villain.LiquexParser

  @doc """
  Controls whether identifiers are persisted to the database.

  ## Example

      persist_identifier true   # Save to database
      persist_identifier false  # Don't persist
  """
  defmacro persist_identifier(persist?) do
    quote location: :keep do
      def __persist_identifier__ do
        unquote(persist?)
      end
    end
  end

  @doc """
  Defines an identifier template for the blueprint.

  The template uses Liquex syntax with `entry` as the context variable.

  ## Examples

      identifier "{{ entry.title }}"

      identifier "{{ entry.title }} [{{ entry.category.name }}]"

  ## Disabling identifiers

      identifier false
      identifier nil
  """
  defmacro identifier(tpl) when is_binary(tpl) do
    {:ok, parsed_identifier} = Liquex.parse(tpl, LiquexParser)
    fields = Template.extract_fields(tpl)

    quote location: :keep do
      if @data_layer == :embedded do
        raise Brando.Exception.BlueprintError, """
        Identifiers are not supported with embedded data layer

        Set `identifier false` in your blueprint to disable identifiers
        """
      end

      def __identifier_fields__, do: unquote(fields)
      def __has_identifier__, do: true

      @parsed_identifier unquote(parsed_identifier)
      def __identifier__(entry, opts \\ []) do
        Brando.Blueprint.Identifier.Generator.generate(
          __MODULE__,
          entry,
          @parsed_identifier,
          opts
        )
      end
    end
  end

  defmacro identifier(nil) do
    quote location: :keep do
      def __has_identifier__, do: false
    end
  end

  defmacro identifier(false) do
    quote location: :keep do
      def __has_identifier__, do: false
    end
  end
end
