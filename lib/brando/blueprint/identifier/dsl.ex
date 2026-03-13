defmodule Brando.Blueprint.Identifier.DSL do
  @moduledoc """
  DSL macros for defining identifiers in blueprints.

  Identifiers generate a title string for entries, used in select inputs,
  multi-selects, entries relation selections, and persisted identifier records.

  The template receives the entry struct — use `@entry` in HEEx or `entry`
  in Liquex templates. Association references (e.g. `@entry.category.name`)
  are automatically detected and included in `__identifier_preloads__/0`.

  ## HEEx

      identifier ~H"{@entry.title}"
      identifier ~H"{@entry.title} [{@entry.category.name}]"

  ## Liquex

      identifier "{{ entry.title }}"
      identifier "{{ entry.title }} [{{ entry.category.name }}]"

  ## Disabling

      identifier false

  ## Persistence

  Identifiers are persisted to the database by default. Disable with:

      persist_identifier false
  """

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

  Accepts either a Liquex template string or a HEEx template using `~H`.

  ## Liquex examples

      identifier "{{ entry.title }}"

      identifier "{{ entry.title }} [{{ entry.category.name }}]"

  ## HEEx examples

      identifier ~H\"""{@entry.title}\"""

      identifier ~H\"""{@entry.title} [{@entry.category.name}]\"""

  ## Disabling identifiers

      identifier false
      identifier nil
  """
  defmacro identifier(tpl) when is_binary(tpl) do
    {:ok, parsed_identifier} = Liquex.parse(tpl, LiquexParser)

    quote location: :keep do
      if @data_layer == :embedded do
        raise Brando.Exception.BlueprintError, """
        Identifiers are not supported with embedded data layer

        Set `identifier false` in your blueprint to disable identifiers
        """
      end

      @identifier_tpl unquote(tpl)
      @identifier_type :liquid
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

  defmacro identifier({:sigil_H, _, [{:<<>>, _, [tpl_string]}, _]} = heex_ast) do
    quote location: :keep do
      @identifier_tpl unquote(tpl_string)
      @identifier_type :heex
      if @data_layer == :embedded do
        raise Brando.Exception.BlueprintError, """
        Identifiers are not supported with embedded data layer

        Set `identifier false` in your blueprint to disable identifiers
        """
      end

      def __has_identifier__, do: true

      def __identifier__(entry, opts \\ []) do
        var!(assigns) = %{entry: entry}

        title =
          unquote(heex_ast)
          |> Phoenix.HTML.Safe.to_iodata()
          |> IO.iodata_to_binary()
          |> String.trim()

        Brando.Blueprint.Identifier.Generator.generate(
          __MODULE__,
          entry,
          title,
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
