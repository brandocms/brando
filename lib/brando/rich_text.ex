defmodule Brando.RichText do
  @moduledoc """
  HTML-preserving validation and identifier-link transformations for rich text.
  Does not rewrite unrelated raw HTML fields or silently strip supported markup.
  """
  alias Ecto.Changeset

  @protocols ~w(http https ftp ftps mailto tel callto sms cid xmpp)
  @unsafe_whitespace ~r/[\x{0000}-\x{0020}\x{007f}-\x{009f}\x{00a0}\x{1680}\x{180e}\x{2000}-\x{202f}\x{205f}\x{3000}\\]/u
  @unsafe_tags ~w(script style iframe object embed form input button textarea select svg math link meta base)

  def allowed_uri?(value) when is_binary(value) and value != "" do
    !Regex.match?(@unsafe_whitespace, value) &&
      case Regex.run(~r/^([a-z][a-z0-9+.-]*):/i, value, capture: :all_but_first) do
        [scheme] -> String.downcase(scheme) in @protocols
        nil -> true
      end
  end

  def allowed_uri?(_), do: false

  def normalize_url(value) when is_binary(value) do
    value = String.trim(value)

    value =
      if Regex.match?(~r/^(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:[\/?#]|$)/i, value), do: "https://" <> value, else: value

    if allowed_uri?(value), do: {:ok, value}, else: {:error, :invalid_url}
  end

  def normalize_url(_), do: {:error, :invalid_url}

  def validate_fields(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      Changeset.validate_change(cs, field, fn _, html ->
        if safe_html?(html), do: [], else: [{field, "contains unsafe rich text or a link with an unsupported address"}]
      end)
    end)
  end

  def validate_blueprint(changeset, module) do
    fields = if function_exported?(module, :__rich_text_fields__, 0), do: module.__rich_text_fields__(), else: []
    validate_fields(changeset, fields)
  end

  def safe_html?(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> Enum.all?(nodes, &safe_node?/1)
      _ -> false
    end
  end

  def safe_html?(nil), do: true
  def safe_html?(_), do: false

  defp safe_node?({tag, attrs, children}) do
    tag not in @unsafe_tags && Enum.all?(attrs, &safe_attribute?/1) && Enum.all?(children, &safe_node?/1)
  end

  defp safe_node?(_), do: true

  defp safe_attribute?({name, value}) do
    cond do
      String.starts_with?(name, "on") -> false
      name in ["href", "src", "xlink:href", "action", "formaction"] -> allowed_uri?(value)
      name == "srcdoc" -> false
      name == "style" -> !Regex.match?(~r/(?:url\s*\(|expression\s*\(|@import|\\)/i, value)
      true -> true
    end
  end

  def update_identifier_url(html, identifier_id, url) when is_binary(html) and is_integer(identifier_id) do
    with true <- allowed_uri?(url), {:ok, nodes} <- Floki.parse_fragment(html) do
      id = to_string(identifier_id)
      matching = Floki.find(nodes, "a[data-identifier-id=\"#{id}\"]")

      if Enum.any?(matching, fn {_, attrs, _} -> List.keyfind(attrs, "href", 0) != {"href", url} end) do
        updated =
          Floki.traverse_and_update(nodes, fn
            {"a", attrs, children} ->
              if List.keyfind(attrs, "data-identifier-id", 0) == {"data-identifier-id", id} do
                {"a", List.keystore(attrs, "href", 0, {"href", url}), children}
              else
                {"a", attrs, children}
              end

            node ->
              node
          end)

        {:updated, Floki.raw_html(updated)}
      else
        :unchanged
      end
    else
      _ -> :unchanged
    end
  end

  def update_identifier_url(_, _, _), do: :unchanged

  def contains_identifier?(html, identifier_id) when is_binary(html) and is_integer(identifier_id) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> Floki.find(nodes, "a[data-identifier-id=\"#{identifier_id}\"]") != []
      _ -> false
    end
  end

  def contains_identifier?(_, _), do: false
end
