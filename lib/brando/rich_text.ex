defmodule Brando.RichText do
  @moduledoc """
  Sanitizing, safety checks and identifier-link transformations for rich text.

  Rich text is parsed as browsers parse it and stored as that parse
  serializes, so what was checked is what browsers build. Comments and the
  elements whose content browsers read differently from other parsers are
  left out; everything else is kept, and markup that is not safe (scripts,
  event handlers, embedded documents, script addresses) is refused rather
  than stripped. Unrelated raw HTML fields are not rewritten.
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
    Enum.reduce(fields, changeset, &sanitize_change(&2, &1))
  end

  # The field stores the sanitized text: what was checked is what browsers
  # parse.
  defp sanitize_change(changeset, field) do
    case Changeset.fetch_change(changeset, field) do
      {:ok, nil} ->
        changeset

      {:ok, html} ->
        case sanitize_html(html) do
          {:ok, ^html} ->
            changeset

          {:ok, clean} ->
            Changeset.put_change(changeset, field, clean)

          :error ->
            Changeset.add_error(changeset, field, "contains unsafe rich text or a link with an unsupported address")
        end

      :error ->
        changeset
    end
  end

  def validate_blueprint(changeset, module) do
    fields = if function_exported?(module, :__rich_text_fields__, 0), do: module.__rich_text_fields__(), else: []
    validate_fields(changeset, fields)
  end

  # Rich text is parsed as browsers parse it, by html5ever (through ammonia,
  # which `MDEx` bundles), and serialized again. The checks below read that
  # serialization, in which every tag, attribute and text is unambiguous, so
  # they see the elements a browser builds, not those another parser builds
  # from the same string.
  #
  # The tags kept for the checks to see: HTML's own (also those refused
  # below), and SVG's. Other tags are left out and their content kept.
  @html_tags ~w(a abbr acronym address area article aside audio b bdi bdo big blockquote br button canvas
                caption center cite code col colgroup data datalist dd del details dfn dialog div dl dt em
                embed fieldset figcaption figure font footer form h1 h2 h3 h4 h5 h6 header hgroup hr i
                iframe img input ins kbd label legend li link main map mark marquee menu meta meter nav
                nobr object ol optgroup option output p picture pre progress q rp rt ruby s samp script
                search section select slot small source span strike strong style sub summary sup table
                tbody td textarea tfoot th thead time tr track tt u ul var video wbr math svg base)
  @svg_tags ~w(svg g path circle ellipse line polyline polygon rect text tspan textPath defs use symbol desc
               metadata linearGradient radialGradient stop clipPath mask pattern image marker filter switch
               view feBlend feColorMatrix feComponentTransfer feComposite feConvolveMatrix
               feDiffuseLighting feDisplacementMap feDistantLight feDropShadow feFlood feFuncA feFuncB
               feFuncG feFuncR feGaussianBlur feImage feMerge feMergeNode feMorphology feOffset
               fePointLight feSpecularLighting feSpotLight feTile feTurbulence foreignObject animate set
               animateMotion animateTransform mpath)
  # Comments, CDATA and the elements whose content browsers read differently
  # from other parsers, or not at all: removed with their content when rich
  # text is sanitized, refused when it is checked.
  @hidden_tags ~w(xmp noembed noframes noscript plaintext template title)
  # Schemes kept for the checks to see, which refuse those not in
  # `@protocols` as before. Ammonia drops an address with any other scheme.
  @schemes @protocols ++
             ~w(javascript vbscript livescript mocha data file blob filesystem about entry ws wss irc ircs
                git ssh sftp news nntp ldap urn geo maps webcal skype viber whatsapp tg signal slack
                msteams zoommtg facetime facetime-audio spotify market intent itms-apps magnet bitcoin
                chrome chrome-extension ms-settings)

  @doc """
  Sanitize rich text: `{:ok, html}` with comments, CDATA and the elements
  in which browsers and other parsers read content differently (`xmp`,
  `noembed`, `noframes`, `noscript`, `plaintext`, `template`, `title`) left
  out, everything else serialized as browsers parse it; or `:error` when it
  holds an unsafe element, attribute or address.
  """
  @spec sanitize_html(term()) :: {:ok, String.t()} | :error
  def sanitize_html(html) when is_binary(html) do
    clean = canonical(html, @html_tags, true)
    if safe_tokens?(clean, @unsafe_tags), do: {:ok, clean}, else: :error
  end

  def sanitize_html(_), do: :error

  @doc """
  Whether `html`, as it is, is safe rich text: no unsafe element,
  attribute or address, and no comment, CDATA or element that
  `sanitize_html/1` would leave out.
  """
  def safe_html?(html) when is_binary(html) do
    case checked_tokens(html, @html_tags ++ @hidden_tags) do
      {:ok, tokens} -> Enum.all?(tokens, &safe_token?(&1, @unsafe_tags ++ @hidden_tags))
      :error -> false
    end
  end

  def safe_html?(nil), do: true
  def safe_html?(_), do: false

  @unsafe_svg_tags ~w(script foreignobject iframe object embed style link meta base animate set handler
                      animatemotion animatetransform)

  @doc """
  Whether `code` is one inline `<svg>` without scripts, event handlers,
  embedded documents or script URLs. Animation elements are refused too:
  they can rewrite an attribute such as `href` after the check.
  """
  def safe_svg?(code) when is_binary(code) do
    # Comments and blank text around the root are allowed, as in an
    # exported icon; inside it, a comment is refused.
    around? = &(match?({:comment, _}, &1) or match?({:text, ""}, trim(&1)))

    with {:ok, tokens} <- checked_tokens(code, @html_tags ++ @svg_tags ++ @hidden_tags),
         [{:start, "svg", _} | _] = tokens <- Enum.drop_while(tokens, around?),
         {:ok, rest} <- close(tokens, 0),
         true <- Enum.all?(rest, around?) do
      tokens
      |> Enum.take(length(tokens) - length(rest))
      |> Enum.all?(&safe_token?(&1, @unsafe_svg_tags ++ (@hidden_tags -- ["title"])))
    else
      _ -> false
    end
  end

  def safe_svg?(_), do: false

  defp trim({:text, text}), do: {:text, String.trim(text)}
  defp trim(token), do: token

  # The tokens after the element the first token opens.
  @void ~w(area base br col embed hr img input link meta param source track wbr keygen)
  defp close([{:start, name, _} | rest], depth) when name in @void, do: close(rest, depth)
  defp close([{:start, _, _} | rest], depth), do: close(rest, depth + 1)
  defp close([{:end, _} | rest], 1), do: {:ok, rest}
  defp close([{:end, _} | rest], depth), do: close(rest, depth - 1)
  defp close([_ | rest], depth), do: close(rest, depth)
  defp close([], _depth), do: :error

  # The checks above see the text as it is stored only after `sanitize_html/1`.
  # Text checked and kept as it is must lose no tag in the canonical form:
  # the attributes of one left out would go unseen (a custom element; `body`,
  # whose attributes a page merges into its own body; table rows outside a
  # table; HTML inside an svg's `desc`). So it may hold no tag name the list
  # lacks, and the canonical form must have, for each name, at least as many
  # start tags as the text has places a browser could read as one, in text
  # and attributes too. Counted by name, so elements a parser adds (a
  # `tbody`, the `br` of `</br>`) do not make up for one it dropped. Tag
  # names are lowercased in ASCII only, as browsers do.
  @tag_name ~r{<([a-zA-Z][^\t\n\f\r />]*)}
  defp checked_tokens(html, tags) do
    known = MapSet.new(tags, &String.downcase(&1, :ascii))
    names = for [name] <- Regex.scan(@tag_name, html, capture: :all_but_first), do: tag_key(name)

    with true <- Enum.all?(names, &(&1 in known or &1 == "img")),
         {:ok, tokens} <- html |> canonical(tags, false) |> String.trim() |> tokens(),
         true <- kept_all?(Enum.frequencies(names), tokens) do
      {:ok, tokens}
    else
      _ -> :error
    end
  end

  # Parsers read `<image>` as `<img>`.
  defp tag_key(name) do
    case String.downcase(name, :ascii) do
      "image" -> "img"
      name -> name
    end
  end

  defp kept_all?(wanted, tokens) do
    kept =
      tokens
      |> Enum.flat_map(fn
        {:start, tag, _} -> [tag_key(tag)]
        _ -> []
      end)
      |> Enum.frequencies()

    Enum.all?(wanted, fn {name, count} -> Map.get(kept, name, 0) >= count end)
  end

  defp canonical(html, tags, strip?) do
    hidden = if strip?, do: @hidden_tags, else: []

    MDEx.safe_html(html,
      sanitize: [
        tags: tags,
        clean_content_tags: hidden,
        generic_attribute_prefixes: [""],
        generic_attributes: [],
        tag_attributes: %{},
        tag_attribute_values: %{},
        url_schemes: @schemes,
        url_relative: :passthrough,
        link_rel: nil,
        allowed_classes: %{},
        strip_comments: strip?,
        id_prefix: nil
      ],
      escape: [content: false, curly_braces_in_code: false]
    )
  end

  defp safe_tokens?(html, refused) do
    case tokens(html) do
      {:ok, tokens} -> Enum.all?(tokens, &safe_token?(&1, refused))
      :error -> false
    end
  end

  defp safe_token?({:start, tag, attrs}, refused),
    do: String.downcase(tag, :ascii) not in refused and Enum.all?(attrs, &safe_attribute?/1)

  defp safe_token?({:comment, _}, _refused), do: false
  defp safe_token?(_token, _refused), do: true

  # The serialization ammonia writes: text without `<`, comments, end tags,
  # and start tags whose attribute values are double-quoted with `&`, `"` and
  # non-breaking spaces escaped. Anything else, such as an attribute name a
  # browser would read differently, fails the check.
  @token ~r{\G(?:([^<]+)|<!--(.*?)-->|</([a-zA-Z][a-zA-Z0-9-]*)>|<([a-zA-Z][a-zA-Z0-9-]*)((?: [a-zA-Z_:][-a-zA-Z0-9_:.]*="[^"]*")*)>)}s
  @attribute ~r{ ([a-zA-Z_:][-a-zA-Z0-9_:.]*)="([^"]*)"}

  defp tokens(html), do: tokens(html, 0, [])

  defp tokens(html, offset, acc) when offset >= byte_size(html), do: {:ok, Enum.reverse(acc)}

  defp tokens(html, offset, acc) do
    case Regex.run(@token, html, offset: offset, capture: :all) do
      [whole, text] -> tokens(html, offset + byte_size(whole), [{:text, text} | acc])
      [whole, "", comment] -> tokens(html, offset + byte_size(whole), [{:comment, comment} | acc])
      [whole, "", _, tag] -> tokens(html, offset + byte_size(whole), [{:end, tag} | acc])
      [whole, "", _, "", tag, attrs] -> tokens(html, offset + byte_size(whole), [{:start, tag, attributes(attrs)} | acc])
      [whole, "", _, "", tag] -> tokens(html, offset + byte_size(whole), [{:start, tag, []} | acc])
      nil -> :error
    end
  end

  defp attributes(attrs) do
    for [_, name, value] <- Regex.scan(@attribute, attrs), do: {String.downcase(name, :ascii), unescape(value)}
  end

  defp unescape(value),
    do: value |> String.replace("&quot;", "\"") |> String.replace("&nbsp;", "\u00a0") |> String.replace("&amp;", "&")

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
      relink_identifier(nodes, to_string(identifier_id), url)
    else
      _ -> :unchanged
    end
  end

  def update_identifier_url(_, _, _), do: :unchanged

  defp relink_identifier(nodes, id, url) do
    matching = Floki.find(nodes, "a[data-identifier-id=\"#{id}\"]")

    if Enum.any?(matching, fn {_, attrs, _} -> List.keyfind(attrs, "href", 0) != {"href", url} end) do
      updated = Floki.traverse_and_update(nodes, &relink_anchor(&1, id, url))
      {:updated, Floki.raw_html(updated)}
    else
      :unchanged
    end
  end

  defp relink_anchor({"a", attrs, children}, id, url) do
    if List.keyfind(attrs, "data-identifier-id", 0) == {"data-identifier-id", id} do
      {"a", List.keystore(attrs, "href", 0, {"href", url}), children}
    else
      {"a", attrs, children}
    end
  end

  defp relink_anchor(node, _id, _url), do: node

  def contains_identifier?(html, identifier_id) when is_binary(html) and is_integer(identifier_id) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> Floki.find(nodes, "a[data-identifier-id=\"#{identifier_id}\"]") != []
      _ -> false
    end
  end

  def contains_identifier?(_, _), do: false
end
