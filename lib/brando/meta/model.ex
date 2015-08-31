defmodule Brando.Meta.Model do
  @moduledoc """
  Meta functions for Brando models

  ## Usage:

      use Brando.Meta.Model,
        [no:
          [singular: "post",
           plural: "poster",
           repr: fn (model) -> "interpolate from model" end,
           fields: [
              id: "ID",
              language: "Språk"]]]

  ## Options:

    * `singular`: The singular form of the models representation
    * `plural`: The plural form of the models representation
    * `repr`: Function returning the repr of the record.
    * `fields`: Keyword list of fields in the model. Used for translation.

  """
  @doc false
  defmacro __using__(opts) do
    shared = define_shared_functions(opts)
    metas = for {language, lang_opts} <- opts do
      define_meta_functions(Atom.to_string(language), lang_opts)
    end
    [shared|metas]
  end

  def define_shared_functions(opts) do
    {_, opts} = List.first(opts)
    quote do
      use Linguist.Vocabulary
      def __fields__ do
        Keyword.keys(unquote(opts[:fields]))
      end
      def __hidden_fields__ do
        unquote(opts[:hidden_fields] || [])
      end
    end
  end

  def define_meta_functions(language, opts) do
    params =
      Keyword.new
      |> Keyword.put(:model, opts[:fields])
      |> put_help(opts)
      |> put_fieldset(opts)

    quote do
      def __name__(unquote(language), :singular), do: unquote(opts[:singular])
      def __name__(unquote(language), :plural), do: unquote(opts[:plural])
      def __repr__(unquote(language), model), do: unquote(opts[:repr]).(model)
      locale unquote(language), unquote(params)
    end
  end

  defp put_help(params, opts) do
    if opts[:help], do: params |> Keyword.put(:help, opts[:help]), else: params
  end

  defp put_fieldset(params, opts) do
    if opts[:fieldset], do: params |> Keyword.put(:fieldset, opts[:fieldset]), else: params
  end
end