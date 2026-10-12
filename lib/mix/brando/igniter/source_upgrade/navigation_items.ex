if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.NavigationItems do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.54 navigation items hold a link var instead of `url`, `title` and
    # `open_in_new_window`, and their sub-items are `children`. A template
    # variable bound by a generator over a navigation's or menu's `items`
    # (`for item <- @navigation.items`, `:for={item <- @menu.items}`), or over
    # such an item's `items` or `children`, is a navigation item. Its reads are
    # rewritten in Elixir code (`Mix.Brando.Igniter.TemplateCode`) when the
    # file binds the name nowhere else; the others stay listed.

    alias Mix.Brando.Igniter.TemplateCode
    alias Rewrite.Source

    @replacements %{
      "url" => "Brando.HTML.get_menu_item_url",
      "title" => "Brando.HTML.get_menu_item_text",
      "open_in_new_window" => "Brando.HTML.get_menu_item_target_blank"
    }

    @generator ~r/\b([a-z_]\w*)\s*<-\s*(@?[\w.\[\]"]*)\.(items|children)\b/

    # A schema of the application's own with `items` (a restaurant's menu,
    # say) may be what `@menu.items` reads, so its reads are only listed.
    @own_items ~r/\b(?:relation|attribute|field|has_many|many_to_many|embeds_many|embeds_one)\s*\(?\s*:items\b/

    @doc "Rewrites the navigation item reads in `paths`."
    def rewrite(igniter, paths) do
      contents = Map.new(paths, &{&1, igniter.rewrite |> Rewrite.source!(&1) |> Source.get(:content)})

      if Enum.any?(contents, fn {path, content} -> Path.extname(path) == ".ex" and content =~ @own_items end),
        do: igniter,
        else: rewrite(igniter, paths, contents)
    end

    defp rewrite(igniter, paths, contents) do
      Enum.reduce(paths, igniter, fn path, igniter ->
        content = contents[path]

        case rewrite_content(content, path) do
          ^content -> igniter
          updated -> Igniter.update_file(igniter, path, &Source.update(&1, :content, updated))
        end
      end)
    end

    @doc "A function of a line of `content`: whether it reads a navigation item the 0.53 way."
    def read?(content) do
      case variables(content) do
        [] -> fn _line -> false end
        # `@item.url` too: an item passed on to a component is read there.
        variables -> &Regex.match?(reads(variables, "(?<![\\w.])"), &1)
      end
    end

    defp rewrite_content(content, path) do
      variables = variables(content)

      case Enum.reject(variables, &bound_elsewhere?(content, &1, variables)) do
        [] ->
          content

        variables ->
          code? = TemplateCode.code?(content, path)

          variables
          |> reads("(?<![\\w.@])")
          |> Regex.scan(content, return: :index)
          |> Enum.filter(fn [{start, _length} | _groups] -> code?.(start) end)
          |> Enum.reverse()
          |> Enum.reduce(content, fn [{start, length}, variable, field], content ->
            replacement = replacement(part(content, variable), part(content, field))

            binary_part(content, 0, start) <>
              replacement <> binary_part(content, start + length, byte_size(content) - start - length)
          end)
      end
    end

    defp part(content, {start, length}), do: binary_part(content, start, length)

    defp replacement(variable, "items"), do: "#{variable}.children"
    defp replacement(variable, field), do: "#{@replacements[field]}(#{variable})"

    defp reads(variables, lookbehind) do
      names = Enum.map_join(variables, "|", &Regex.escape/1)
      Regex.compile!(lookbehind <> "(#{names})\\.(url|title|open_in_new_window|items)(?![\\w?!(])")
    end

    # Generators over a navigation's or menu's items, then over those items'
    # own items, until no new variable turns up.
    defp variables(content) do
      generators = Regex.scan(@generator, content, capture: :all_but_first)
      variables(generators, [])
    end

    defp variables(generators, found) do
      more =
        for [variable, source, _field] <- generators,
            variable not in found,
            item_source?(source, found),
            uniq: true,
            do: variable

      if more == [], do: Enum.sort(found), else: variables(generators, found ++ more)
    end

    defp item_source?(source, variables), do: source =~ ~r/nav|menu/i or source in variables

    # A name the file also binds to something else, in any pattern: another
    # generator (`{item, index} <- …`), a match (`%{product: item} = …`), a
    # clause (`fn {item, _} ->`, `{:ok, item} ->`), a function argument or
    # `:let`.
    defp bound_elsewhere?(content, variable, variables) do
      name = ~r/(?<![\w.@:])#{Regex.escape(variable)}(?![\w:.(])/

      item_generators =
        for [^variable, source, _field] <- Regex.scan(@generator, content, capture: :all_but_first),
            item_source?(source, variables),
            do: source

      generators = for pattern <- patterns(content, ~r/<-/), pattern =~ name, do: pattern

      length(generators) > length(item_generators) or
        Enum.any?(patterns(content, ~r/(?<![=!<>~%])=(?![=~>{"])|->/), &(&1 =~ name)) or
        Regex.match?(~r/:let=\{[^}]*#{Regex.source(name)}/, content) or
        Regex.match?(~r/\bdefp?\s+\w+[?!]?\(([^)]*[\s,({\[])?#{Regex.escape(variable)}\b/, content)
    end

    # The pattern left of each `operator`: back to a comma, an opening
    # bracket or the start of the line outside brackets, less a leading
    # `for`, `with`, `fn` or `case` keyword.
    defp patterns(content, operator) do
      for [{start, _length}] <- Regex.scan(operator, content, return: :index) do
        content
        |> binary_part(0, start)
        |> String.reverse()
        |> String.graphemes()
        |> take_pattern(0, [])
        |> String.replace(~r/^\s*(?:for|with|fn|case|<%=?|<%|%>)\s+/, "")
      end
    end

    defp take_pattern([], _depth, taken), do: Enum.join(taken)
    defp take_pattern(["\n" | _rest], 0, taken), do: Enum.join(taken)
    defp take_pattern(["," | _rest], 0, taken), do: Enum.join(taken)
    defp take_pattern([char | _rest], 0, taken) when char in ["(", "[", "{"], do: Enum.join(taken)

    defp take_pattern([char | rest], depth, taken) when char in [")", "]", "}"],
      do: take_pattern(rest, depth + 1, [char | taken])

    defp take_pattern([char | rest], depth, taken) when char in ["(", "[", "{"],
      do: take_pattern(rest, depth - 1, [char | taken])

    defp take_pattern([char | rest], depth, taken), do: take_pattern(rest, depth, [char | taken])
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.NavigationItems do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
