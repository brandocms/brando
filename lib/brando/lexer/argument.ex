defmodule Brando.Lexer.Argument do
  @moduledoc false

  alias Brando.Lexer.Context
  alias Brando.Globals
  alias Brando.Pages

  @type field_t :: any
  @type argument_t ::
          {:field, [field_t]}
          | {:literal, field_t}
          | {:inclusive_range, [begin: field_t, end: field_t]}

  @spec eval(argument_t | [argument_t], Context.t()) :: field_t
  def eval([argument], context), do: eval(argument, context)

  def eval({:field, accesses}, %Context{variables: variables}),
    do: do_eval(variables, accesses)

  def eval({:literal, literal}, _context), do: literal

  def eval({:inclusive_range, [begin: begin_value, end: end_value]}, context),
    do: eval(begin_value, context)..eval(end_value, context)

  def eval({:keyword, [key, value]}, context), do: {key, eval(value, context)}

  defp do_eval(value, []), do: value
  defp do_eval(nil, _), do: nil

  # Special case ":first"
  #! TODO: Maybe move to a filter?
  defp do_eval(value, [{:key, "first"} | tail]) when is_list(value) do
    value
    |> Enum.at(0)
    |> do_eval(tail)
  end

  # Special case ":size"
  #! TODO: Maybe move to a filter?
  defp do_eval(value, [{:key, "size"} | tail]) when is_list(value) do
    value
    |> length()
    |> do_eval(tail)
  end

  # ${global:category.key}
  defp do_eval(_, [{:key, "global"} | [{:key, category}, {:key, key}]]) do
    global = Globals.get_global!("#{category}.#{key}")
    do_eval(global, [])
  end

  # ${link:instagram.*}
  defp do_eval(value, [{:key, "link"} | [{:key, link} | tail]]) do
    links = Map.get(value, "links")
    link = Enum.find(links, &(String.downcase(&1.name) == link))
    do_eval(link, tail)
  end

  # ${fragment:parent_key/key/language}
  defp do_eval(_, [{:key, "fragment"} | [{:key, search_path}]]) do
    with [parent_key, key, lang] <- String.split(search_path, "/"),
         {:ok, fragment} <- Pages.get_page_fragment(parent_key, key, lang) do
      fragment
      |> Phoenix.HTML.Safe.to_iodata()
      |> do_eval([])
    else
      [_] ->
        #! TODO: ADD TO ETS WARNINGS: "==> WRONG FRAGMENT FORMAT: #{search_path}"
        ""

      {:error, {:page_fragment, :not_found}} ->
        #! TODO: ADD TO ETS WARNINGS: "==> MISSING FRAGMENT: #{search_path} <=="
        ""
    end
  end

  defp do_eval(struct, [{:key, key} | tail]) when is_struct(struct) do
    atom_key = safe_to_existing_atom(key)

    struct
    |> Map.get(atom_key)
    |> do_eval(tail)
  end

  defp do_eval(value, [{:key, key} | tail]) do
    value
    |> Map.get(key)
    |> do_eval(tail)
  end

  defp do_eval(value, [{:accessor, accessor} | tail]) do
    value
    |> Enum.at(accessor)
    |> do_eval(tail)
  end

  def safe_to_existing_atom(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> ""
    end
  end
end
