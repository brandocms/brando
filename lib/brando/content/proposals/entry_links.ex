defmodule Brando.Content.Proposals.EntryLinks do
  @moduledoc """
  Links to entries in rich text a proposal writes.

  An agent writes `<a href="entry:Brando.Pages.Page:12">…</a>`. When a
  proposal is prepared, each such link becomes what the editor's link picker
  makes: the entry's address and its identifier,
  `<a href="/about" data-identifier-id="34">`, so the link follows the entry
  when its address changes. A link to an entry the actor cannot read, or one
  without an identifier, is left as it is; `unresolved?/1` finds it, and the
  proposal reports it.
  """
  alias Brando.Content
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Transfer.{Catalog, Error}

  @link ~r/href=(["'])entry:([^"':]+):(\d+)\1/

  @doc "Resolve entry links in every text an operation writes."
  @spec resolve(struct(), term()) :: struct()
  def resolve(op, actor) do
    op
    |> update(:texts, &Map.new(&1, fn {key, text} -> {key, text(text, actor)} end))
    |> update(:text, &text(&1, actor))
    |> update(:fields, &Map.new(&1, fn {key, value} -> {key, text(value, actor)} end))
    |> update(:values, &Map.new(&1, fn {key, value} -> {key, text(value, actor)} end))
  end

  defp update(op, key, fun) do
    case Map.fetch(op, key) do
      {:ok, value} when not is_nil(value) -> Map.put(op, key, fun.(value))
      _ -> op
    end
  end

  defp text(text, actor) when is_binary(text) do
    if String.contains?(text, "entry:") do
      Regex.replace(@link, text, fn whole, quote, name, id -> link(whole, quote, name, String.to_integer(id), actor) end)
    else
      text
    end
  end

  defp text(value, _actor), do: value

  defp link(whole, quote, name, id, actor) do
    with {:ok, schema} <- Codec.schema(name),
         {:ok, _entry} <- Error.protect(fn -> Catalog.load!(schema, id, actor, :read) end),
         {:ok, %{id: identifier_id, url: url}} when is_binary(url) <- Content.get_identifier(schema, %{id: id}) do
      ~s(href=#{quote}#{url}#{quote} data-identifier-id=#{quote}#{identifier_id}#{quote})
    else
      _ -> whole
    end
  end

  @doc "Whether `value` still holds an entry link that could not be resolved."
  @spec unresolved?(term()) :: boolean()
  def unresolved?(value) when is_binary(value), do: Regex.match?(~r/href=(["'])\s*entry:/i, value)
  def unresolved?(_), do: false
end
