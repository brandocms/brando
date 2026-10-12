if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.ListingRows do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.53 listings declared their rows as columns: `field :cover, :image`,
    # `field :language, :language`, `field :url, :url` and Liquid `template`s.
    # Since 0.54 a row is a function component (`component
    # &__MODULE__.listing_row/1`), and the columns render nothing.
    #
    # A listing whose every column has an equivalent becomes one row component,
    # appended to the module:
    #
    #   * an `:image` field is `Cover.cover/1`, with its `padded`, `circular`
    #     and `top` classes as the component's flags;
    #   * a `:url` field is `Core.url/1`;
    #   * a `:language` field is dropped: a listing shows the content language
    #     only;
    #   * a template whose one link is the entry's admin update URL is
    #     `Core.update_link/1`, the markup before the link its `:before` slot
    #     and the markup after it its `:outside` slot; a template without a
    #     link is `Core.field/1`.
    #
    # Templates convert from a Liquid subset: `{{ entry.a.b }}` (also
    # `entry.a[0].b`, and in attributes), `{% if entry.a %}` and
    # `{% for x in entry.a %}` around one element or around text. Inline `<svg>`
    # icons in a `.badge` are dropped, since 0.55's badge wraps them onto a
    # line of their own. Any other column, Liquid or markup leaves the whole
    # listing as it is, and is listed with file and line.

    alias Igniter.Code.Common
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Rewrite.Source
    alias Sourceror.Zipper

    @guide "guides/blueprint_listings.md#rows"
    @void_elements ~w(area base br col embed hr img input link meta source track wbr)
    @attributes Regex.source(~r/(?:\s+[^\s"'<>\/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*/)
    @token Regex.compile!(
             Regex.source(~r/\{\{.*?\}\}|\{%.*?%\}|<!--.*?-->|<\/[a-zA-Z][\w:-]*\s*>|<[a-zA-Z][\w:-]*/) <>
               @attributes <> ~S"\s*/?>",
             "s"
           )
    @output ~r/\A\{\{-?\s*(.*?)\s*-?\}\}\z/s
    @tag ~r/\A\{%-?\s*(.*?)\s*-?%\}\z/s
    @comment ~r/\A<!--.*-->\z/s
    @close ~r/\A<\/([a-zA-Z][\w:-]*)\s*>\z/
    @open Regex.compile!(~S"\A<([a-zA-Z][\w:-]*)(" <> @attributes <> ~S")\s*(/?)>\z", "s")
    @attribute ~r/([^\s"'<>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/
    @liquid_path ~r/\A([a-z_]\w*)((?:\.[a-z_]\w*(?:\[\d+\])?)*)\z/
    @for_clause ~r/\A([a-z_]\w*)\s+in\s+(\S+)\z/
    @update_href ~r/\A\/admin\/\S+\/update\/\{\{-?\s*entry\.id\s*-?\}\}\z/
    @link_attributes ~w(href class data-phx-link data-phx-link-state)

    @doc """
    Rewrites every Blueprint listing whose `field` and `template` columns all
    have a row component equivalent, notes what it dropped, and warns, with
    file and line, about the listings it left.
    """
    def rewrite(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)

      {igniter, findings} =
        Enum.reduce(blueprints, {igniter, []}, fn module, {igniter, findings} ->
          {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
          path = Source.get(source, :path)

          case rewrite_module(zipper, path) do
            {:ok, zipper, found} ->
              {Igniter.update_elixir_file(igniter, path, fn _zipper -> {:ok, zipper} end), findings ++ found}

            {:unchanged, found} ->
              {igniter, findings ++ found}
          end
        end)

      igniter
      |> add_notice(findings)
      |> add_warning(Keyword.get_values(findings, :manual))
    end

    defp rewrite_module(zipper, path) do
      defined = defined_functions(Zipper.node(zipper))
      {module, rows} = Macro.prewalk(Zipper.node(zipper), [], &rewrite_listing(&1, &2, path, defined))

      {converted, findings} =
        rows
        |> Enum.reverse()
        |> Enum.split_with(&match?({:row, _function, _heex}, &1))

      case converted do
        [] -> {:unchanged, findings}
        rows -> append_rows(Zipper.replace(zipper, module), rows, path, findings)
      end
    end

    # Each row function goes at the end of the module, with the imports its
    # components need.
    defp append_rows(zipper, rows, path, findings) do
      {:ok, body} = Common.move_to_do_block(zipper)

      body =
        Enum.reduce(rows, body, fn {:row, function, heex}, body ->
          Common.add_code(body, row_function(function, heex), placement: :after)
        end)

      case SourceUpgrade.add_listing_component_imports(body) do
        {:ok, zipper} -> {:ok, zipper, findings}
        {:warning, warning} -> {:ok, body, findings ++ [manual: "#{path}: #{warning}"]}
      end
    end

    defp row_function(function, heex) do
      """
      def #{function}(assigns) do
        ~H\"\"\"
      #{heex |> String.split("\n") |> Enum.map_join("\n", &indent/1)}
        \"\"\"
      end
      """
    end

    defp indent(""), do: ""
    defp indent(line), do: "  " <> line

    defp rewrite_listing({:listing, meta, args} = node, acc, path, defined) when is_list(args) do
      with {:ok, name, statements, put_statements} <- listing_body(args),
           [_ | _] = columns <- Enum.filter(statements, &column?/1) do
        function = row_function_name(name)

        case convert_listing(statements, columns, function, meta, defined) do
          {:ok, heex, notes, statements} ->
            location = listing_location(path, name)
            findings = [{:converted, location} | Enum.map(notes, &{&1, location})]
            {{:listing, meta, put_statements.(statements)}, [{:row, function, heex} | Enum.reverse(findings, acc)]}

          {:error, line, reason} ->
            {node, [{:manual, "#{path}:#{line}: #{reason}"} | acc]}
        end
      else
        _ -> {node, acc}
      end
    end

    defp rewrite_listing(node, acc, _path, _defined), do: {node, acc}

    defp listing_location(path, :default), do: path
    defp listing_location(path, name), do: "#{path} (listing #{inspect(name)})"

    defp convert_listing(statements, columns, function, meta, defined) do
      cond do
        Enum.any?(statements, &match?({:component, _, [_]}, &1)) ->
          {:error, meta[:line], "the listing also has a `component`"}

        MapSet.member?(defined, {function, 1}) ->
          {:error, meta[:line], "the module already defines `#{function}/1`"}

        true ->
          with {:ok, heex, notes} <- row(columns) do
            {:ok, heex, notes, replace_columns(statements, function)}
          end
      end
    end

    # The component takes the first column's place; the other columns go.
    defp replace_columns(statements, function) do
      {before, [{_call, meta, _args} | rest]} = Enum.split_while(statements, &(not column?(&1)))
      before ++ [component_call(function, meta[:line]) | Enum.reject(rest, &column?/1)]
    end

    defp listing_body([block]), do: listing_body(:default, [], block)

    defp listing_body([{:__block__, _, [name]} = argument, block]) when is_atom(name),
      do: listing_body(name, [argument], block)

    defp listing_body(_args), do: :error

    defp listing_body(name, arguments, [{{:__block__, do_meta, [:do]}, body}]) do
      statements =
        case body do
          {:__block__, _, statements} when is_list(statements) -> statements
          statement -> [statement]
        end

      put_statements = fn statements ->
        arguments ++ [[{{:__block__, do_meta, [:do]}, {:__block__, block_meta(body), statements}}]]
      end

      {:ok, name, statements, put_statements}
    end

    defp listing_body(_name, _arguments, _block), do: :error

    defp block_meta({:__block__, meta, statements}) when is_list(statements), do: meta
    defp block_meta(_statement), do: []

    defp row_function_name(:default), do: :listing_row
    defp row_function_name(name), do: :"#{name}_listing_row"

    defp component_call(function, line) do
      "component &__MODULE__.#{function}/1"
      |> Sourceror.parse_string!()
      |> Macro.prewalk(fn
        {form, meta, args} when is_list(meta) -> {form, Keyword.put(meta, :line, line), args}
        node -> node
      end)
    end

    defp column?({:field, _, [_name, _type]}), do: true
    defp column?({:field, _, [_name, _type, _options]}), do: true
    defp column?({:template, _, [_template]}), do: true
    defp column?({:template, _, [_template, _options]}), do: true
    defp column?(_statement), do: false

    defp defined_functions(ast) do
      {_ast, functions} =
        Macro.prewalk(ast, MapSet.new(), fn
          {kind, _, [{:when, _, [{name, _, args} | _]} | _]} = node, acc when kind in [:def, :defp] and is_list(args) ->
            {node, MapSet.put(acc, {name, length(args)})}

          {kind, _, [{name, _, args} | _]} = node, acc when kind in [:def, :defp] and is_atom(name) and is_list(args) ->
            {node, MapSet.put(acc, {name, length(args)})}

          node, acc ->
            {node, acc}
        end)

      functions
    end

    ## Columns

    defp row(columns) do
      line = columns |> hd() |> elem(1) |> Keyword.get(:line)

      columns
      |> Enum.reduce_while({[], []}, fn {_call, meta, _args} = column, {cells, notes} ->
        case cell(column) do
          {:ok, cell, column_notes} -> {:cont, {cells ++ List.wrap(cell), notes ++ column_notes}}
          {:error, reason} -> {:halt, {:error, meta[:line], reason}}
        end
      end)
      |> case do
        {:error, _line, _reason} = error ->
          error

        {[], _notes} ->
          {:error, line, "no column other than the language"}

        {cells, notes} ->
          case format(Enum.join(cells, "\n")) do
            {:ok, heex} -> {:ok, heex, Enum.uniq(notes)}
            :error -> {:error, line, "markup that does not convert to valid HEEx"}
          end
      end
    end

    defp format(heex) do
      {:ok, heex |> Phoenix.LiveView.HTMLFormatter.format([]) |> String.trim_trailing()}
    rescue
      _error -> :error
    end

    defp cell({:field, _, [name, type | options]}) do
      with {:ok, name} <- literal_atom(name, "a field name that is not an atom"),
           {:ok, type} <- literal_atom(type, "a field type that is not an atom"),
           {:ok, options} <- literal_options(options) do
        field_cell(name, type, options)
      end
    end

    defp cell({:template, _, [template | options]}) do
      with {:ok, template} <- literal_string(template),
           {:ok, options} <- literal_options(options),
           {:ok, attributes} <- cell_attributes(options, "a template") do
        template_cell(template, attributes)
      end
    end

    defp field_cell(_name, :language, _options), do: {:ok, nil, [:language]}

    defp field_cell(name, :image, options) do
      with {:ok, columns} <- columns(options, "an image field"),
           :ok <- known_options(options, [:columns, :class, :offset, :size], "an image field") do
        classes = options |> Keyword.get(:class, "") |> String.split()
        {flags, classes} = Enum.split_with(classes, &(&1 in ~w(padded circular top)))

        attributes =
          ["image={@entry.#{name}}", "columns={#{columns}}"] ++
            optional("size", options[:size]) ++
            optional("offset", options[:offset]) ++
            Enum.uniq(flags) ++ optional("class", Enum.join(classes, " "))

        {:ok, "<.cover #{Enum.join(attributes, " ")} />", []}
      end
    end

    defp field_cell(_name, :url, options) do
      with :ok <- known_options(options, [:columns, :class, :offset], "a url field") do
        attributes = ["entry={@entry}"] ++ optional("offset", options[:offset]) ++ optional("class", options[:class])
        {:ok, "<.url #{Enum.join(attributes, " ")} />", []}
      end
    end

    defp field_cell(_name, type, _options), do: {:error, "a `#{inspect(type)}` field"}

    defp cell_attributes(options, column) do
      with {:ok, columns} <- columns(options, column),
           :ok <- known_options(options, [:columns, :class, :offset], column) do
        {:ok, ["columns={#{columns}}"] ++ optional("offset", options[:offset]) ++ optional("class", options[:class])}
      end
    end

    defp columns(options, column) do
      case options[:columns] do
        columns when is_integer(columns) -> {:ok, columns}
        _other -> {:error, "#{column} without a literal `columns:`"}
      end
    end

    defp known_options(options, known, column) do
      case Keyword.keys(options) -- known do
        [] -> :ok
        [key | _] -> {:error, "the `#{key}:` option of #{column}"}
      end
    end

    defp optional(_name, nil), do: []
    defp optional(_name, ""), do: []
    defp optional(name, value) when is_binary(value), do: ["#{name}=#{inspect(value)}"]
    defp optional(name, value) when is_integer(value), do: ["#{name}={#{value}}"]
    defp optional(name, value) when is_atom(value), do: ["#{name}={#{inspect(value)}}"]

    defp literal_atom({:__block__, _, [value]}, _reason) when is_atom(value), do: {:ok, value}
    defp literal_atom(value, _reason) when is_atom(value), do: {:ok, value}
    defp literal_atom(_value, reason), do: {:error, reason}

    defp literal_string({:__block__, _, [value]}) when is_binary(value), do: {:ok, value}
    defp literal_string(_value), do: {:error, "a template that is not a literal string"}

    defp literal_options([]), do: {:ok, []}

    defp literal_options([options]) when is_list(options) do
      Enum.reduce_while(options, {:ok, []}, fn
        {{:__block__, _, [key]}, {:__block__, _, [value]}}, {:ok, acc}
        when is_atom(key) and (is_binary(value) or is_integer(value) or is_atom(value)) ->
          {:cont, {:ok, acc ++ [{key, value}]}}

        {{:__block__, _, [key]}, _value}, _acc ->
          {:halt, {:error, "the `#{key}:` option is not a literal"}}

        _option, _acc ->
          {:halt, {:error, "options that are not a literal keyword list"}}
      end)
    end

    defp literal_options(_options), do: {:error, "options that are not a literal keyword list"}

    ## Templates

    defp template_cell(template, attributes) do
      with {:ok, nodes} <- parse(template),
           {nodes, icons} = drop_badge_icons(nodes),
           {:ok, cell} <- template_markup(trim(nodes), attributes) do
        {:ok, cell, if(icons, do: [:svg], else: [])}
      end
    end

    defp template_markup(nodes, attributes) do
      case Enum.split_while(nodes, &(not link?(&1))) do
        {before, [{:element, "a", link_attributes, content} | after_link]} ->
          with :ok <- one_link(before ++ content ++ after_link),
               :ok <- update_link(link_attributes),
               {:ok, before} <- render_block(before),
               {:ok, content} <- render_block(content),
               {:ok, outside} <- render_block(after_link) do
            {:ok, update_link_cell(attributes, before, content, outside)}
          end

        {nodes, []} ->
          with :ok <- one_link(nodes),
               {:ok, content} <- render_block(nodes) do
            {:ok, wrap("<.field #{Enum.join(attributes, " ")}>", content, "</.field>")}
          end
      end
    end

    defp update_link_cell(attributes, "", content, ""),
      do: wrap("<.update_link entry={@entry} #{Enum.join(attributes, " ")}>", content, "</.update_link>")

    # Markup before the link goes in the `:before` slot, markup after it in
    # `:outside`, which renders after the link inside the same cell.
    defp update_link_cell(attributes, before, content, outside) do
      Enum.join(
        ["<.update_link entry={@entry} #{Enum.join(attributes, " ")}>"] ++
          slot("before", before) ++ [content] ++ slot("outside", outside) ++ ["</.update_link>"],
        "\n"
      )
    end

    defp slot(_name, ""), do: []
    defp slot(name, content), do: ["<:#{name}>", content, "</:#{name}>"]

    defp wrap(open, content, close) do
      if String.contains?(content, "\n"),
        do: Enum.join([open, content, close], "\n"),
        else: open <> content <> close
    end

    defp link?({:element, "a", _attributes, _children}), do: true
    defp link?(_node), do: false

    defp one_link(nodes) do
      if Enum.any?(nodes, &contains_link?/1),
        do: {:error, "a template with a link that is not its only one, or inside other markup"},
        else: :ok
    end

    defp contains_link?({:element, "a", _attributes, _children}), do: true

    defp contains_link?({:element, _name, _attributes, children}) when is_list(children),
      do: Enum.any?(children, &contains_link?/1)

    defp contains_link?({:if, _condition, children}), do: Enum.any?(children, &contains_link?/1)
    defp contains_link?({:for, _variable, _collection, children}), do: Enum.any?(children, &contains_link?/1)
    defp contains_link?(_node), do: false

    defp update_link(attributes) do
      href = List.keyfind(attributes, "href", 0)

      cond do
        Enum.any?(attributes, fn {name, _value} -> name not in @link_attributes end) ->
          {:error, "a link with attributes other than `href` and `class`"}

        not match?({_, href} when is_binary(href), href) or not Regex.match?(@update_href, elem(href, 1)) ->
          {:error, "a link that is not to the entry's update form (`/admin/…/update/{{ entry.id }}`)"}

        List.keyfind(attributes, "class", 0) not in [nil, {"class", "entry-link"}] ->
          {:error, "a link with a class other than `entry-link`"}

        true ->
          :ok
      end
    end

    ## Liquid and HTML

    defp parse(template) do
      @token
      |> Regex.split(template, include_captures: true, trim: true)
      |> Enum.map(&token/1)
      |> build([{:root, []}])
    end

    defp token(text) do
      cond do
        match = Regex.run(@output, text) -> {:output, Enum.at(match, 1)}
        match = Regex.run(@tag, text) -> {:tag, Enum.at(match, 1)}
        Regex.match?(@comment, text) -> {:comment, text}
        match = Regex.run(@close, text) -> {:close, Enum.at(match, 1)}
        match = Regex.run(@open, text) -> open_token(match)
        true -> {:text, text}
      end
    end

    defp open_token([_text, name, attributes, self_closing]) do
      attributes =
        for [_match, name | values] <- Regex.scan(@attribute, attributes),
            do: {name, attribute_value(values)}

      {:open, name, attributes, self_closing == "/" or String.downcase(name) in @void_elements}
    end

    defp attribute_value([]), do: nil
    defp attribute_value(values), do: Enum.find(values, "", &(&1 != ""))

    defp build([], [{:root, children}]), do: {:ok, Enum.reverse(children)}
    defp build([], [{:if, _condition, _children} | _stack]), do: {:error, "a `{% if %}` without `{% endif %}`"}

    defp build([], [{:for, _variable, _collection, _children} | _stack]),
      do: {:error, "a `{% for %}` without `{% endfor %}`"}

    defp build([], [{{:element, name, _}, _children} | _stack]), do: {:error, "an unclosed `<#{name}>`"}

    defp build([{:open, name, attributes, true} | tokens], stack),
      do: build(tokens, add({:element, name, attributes, :void}, stack))

    defp build([{:open, name, attributes, false} | tokens], stack),
      do: build(tokens, [{{:element, name, attributes}, []} | stack])

    defp build([{:close, name} | tokens], [{{:element, name, attributes}, children} | stack]),
      do: build(tokens, add({:element, name, attributes, Enum.reverse(children)}, stack))

    defp build([{:close, name} | _tokens], _stack), do: {:error, "an unmatched `</#{name}>`"}

    defp build([{:tag, "if " <> condition} | tokens], stack),
      do: build(tokens, [{:if, String.trim(condition), []} | stack])

    defp build([{:tag, "endif"} | tokens], [{:if, condition, children} | stack]),
      do: build(tokens, add({:if, condition, Enum.reverse(children)}, stack))

    defp build([{:tag, "for " <> clause = tag} | tokens], stack) do
      case Regex.run(@for_clause, clause) do
        [_clause, variable, collection] -> build(tokens, [{:for, variable, collection, []} | stack])
        nil -> {:error, "the Liquid tag `{% #{tag} %}`"}
      end
    end

    defp build([{:tag, "endfor"} | tokens], [{:for, variable, collection, children} | stack]),
      do: build(tokens, add({:for, variable, collection, Enum.reverse(children)}, stack))

    defp build([{:tag, tag} | _tokens], _stack), do: {:error, "the Liquid tag `{% #{tag} %}`"}
    defp build([node | tokens], stack), do: build(tokens, add(node, stack))

    defp add(node, [{:root, children} | stack]), do: [{:root, [node | children]} | stack]
    defp add(node, [{:if, condition, children} | stack]), do: [{:if, condition, [node | children]} | stack]

    defp add(node, [{:for, variable, collection, children} | stack]),
      do: [{:for, variable, collection, [node | children]} | stack]

    defp add(node, [{element, children} | stack]), do: [{element, [node | children]} | stack]

    # 0.55's `.badge` lays an icon out on a line of its own.
    defp drop_badge_icons(nodes) do
      Enum.map_reduce(nodes, false, fn
        {:element, name, attributes, children}, dropped when is_list(children) ->
          {children, icons} =
            if badge?(attributes),
              do:
                {Enum.reject(children, &match?({:element, "svg", _, _}, &1)),
                 Enum.any?(children, &match?({:element, "svg", _, _}, &1))},
              else: drop_badge_icons(children)

          {{:element, name, attributes, merge_blanks(children)}, dropped or icons}

        {:if, condition, children}, dropped ->
          {children, icons} = drop_badge_icons(children)
          {{:if, condition, children}, dropped or icons}

        {:for, variable, collection, children}, dropped ->
          {children, icons} = drop_badge_icons(children)
          {{:for, variable, collection, children}, dropped or icons}

        node, dropped ->
          {node, dropped}
      end)
    end

    defp badge?(attributes) do
      case List.keyfind(attributes, "class", 0) do
        {"class", class} when is_binary(class) -> "badge" in String.split(class)
        _other -> false
      end
    end

    defp merge_blanks([{:text, _} = first, {:text, _} = second | rest]) do
      if blank?(first) and blank?(second), do: merge_blanks([first | rest]), else: [first | merge_blanks([second | rest])]
    end

    defp merge_blanks([node | rest]), do: [node | merge_blanks(rest)]
    defp merge_blanks([]), do: []

    defp blank?({:text, text}), do: String.trim(text) == ""
    defp blank?(_node), do: false

    defp trim(nodes) do
      nodes |> Enum.drop_while(&blank?/1) |> Enum.reverse() |> Enum.drop_while(&blank?/1) |> Enum.reverse()
    end

    # Elements go on lines of their own; text and values keep their spacing.
    # `scope` holds the loop variables in reach and the Liquid paths an
    # enclosing `{% if %}` already tested.
    defp render_block(nodes, scope \\ %{variables: [], tested: []}) do
      with {:ok, parts} <- render_all(trim(nodes), scope) do
        {:ok, join_block(parts, nil, "")}
      end
    end

    defp join_block([], _previous, acc), do: acc

    defp join_block([{:space, _} | rest], :element, acc), do: join_block(rest, :element, acc)

    defp join_block([{:space, _} | [{:element, _} | _] = rest], previous, acc), do: join_block(rest, previous, acc)

    defp join_block([{kind, text} | rest], previous, acc) do
      text = if previous == :element, do: String.trim_leading(text), else: text
      text = if match?([{:element, _} | _], rest) and kind != :element, do: String.trim_trailing(text), else: text
      separator = if previous != nil and :element in [kind, previous], do: "\n", else: ""
      join_block(rest, kind, acc <> separator <> text)
    end

    defp render_inline(nodes, scope) do
      with {:ok, parts} <- render_all(nodes, scope) do
        {:ok, Enum.map_join(parts, &elem(&1, 1))}
      end
    end

    defp render_all(nodes, scope) do
      Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, parts} ->
        case render(node, scope) do
          {:ok, part} -> {:cont, {:ok, parts ++ [part]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end

    defp render({:text, text}, _scope) do
      cond do
        String.contains?(text, ["{", "}"]) -> {:error, "a `{` or `}` in the template's text"}
        String.trim(text) == "" -> {:ok, {:space, text}}
        true -> {:ok, {:text, text}}
      end
    end

    defp render({:comment, comment}, _scope), do: {:ok, {:element, comment}}

    defp render({:output, expression}, scope) do
      with {:ok, expression} <- entry_expression(expression, "{{ #{expression} }}", scope) do
        {:ok, {:text, "{#{expression}}"}}
      end
    end

    defp render({:element, _name, _attributes, _children} = element, scope), do: render_element(element, [], scope)

    defp render({:if, condition, children}, scope) do
      with {:ok, expression} <- entry_expression(condition, "{% if #{condition} %}", scope) do
        scope = %{scope | tested: [String.trim(condition) | scope.tested]}
        render_wrapped(trim(children), ":if={#{expression}}", "{% if #{condition} %}", scope)
      end
    end

    # A `{% for %}` over an association of the entry, or of a loop variable.
    defp render({:for, variable, collection, children}, scope) do
      shown = "{% for #{variable} in #{collection} %}"

      with {:ok, expression} <- entry_expression(collection, shown, scope) do
        expression = if String.contains?(expression, " && "), do: "(#{expression}) || []", else: expression
        scope = %{scope | variables: [variable | scope.variables]}
        render_wrapped(trim(children), ":for={#{variable} <- #{expression}}", shown, scope)
      end
    end

    # One element takes the `:if` or `:for`; text is wrapped in a `<span>`
    # that does.
    defp render_wrapped([{:element, _name, _attributes, _children} = element], attribute, _shown, scope),
      do: render_element(element, [attribute], scope)

    defp render_wrapped(children, attribute, shown, scope) do
      with true <- Enum.all?(children, &match?({kind, _} when kind in [:text, :output], &1)),
           {:ok, text} <- render_inline(children, scope) do
        {:ok, {:element, "<span #{attribute}>#{String.trim(text)}</span>"}}
      else
        false -> {:error, "a `#{shown}` around more than one element, or around an element and text"}
        {:error, _reason} = error -> error
      end
    end

    defp render_element({:element, name, attributes, children}, extra, scope) do
      with {:ok, attributes} <- render_attributes(name, attributes, scope) do
        open = Enum.join([name | extra] ++ attributes, " ")

        if children == :void do
          {:ok, {:element, "<#{open} />"}}
        else
          with {:ok, inner} <- render_inline(children, scope) do
            {:ok, {:element, "<#{open}>#{inner}</#{name}>"}}
          end
        end
      end
    end

    defp render_attributes(element, attributes, scope) do
      Enum.reduce_while(attributes, {:ok, []}, fn attribute, {:ok, rendered} ->
        case attribute(attribute, element, scope) do
          {:ok, attribute} -> {:cont, {:ok, rendered ++ [attribute]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end

    defp attribute({name, nil}, _element, _scope), do: {:ok, name}

    defp attribute({name, value}, element, scope) do
      cond do
        not String.contains?(value, ["{", "}"]) ->
          {:ok, if(String.contains?(value, "\""), do: "#{name}='#{value}'", else: "#{name}=\"#{value}\"")}

        String.contains?(value, "{%") ->
          {:error, "a Liquid tag in the attributes of a `<#{element}>`"}

        true ->
          liquid_attribute(name, value, element, scope)
      end
    end

    # `{{ entry.x }}` in an attribute becomes an expression, and text around
    # it a string with the value interpolated.
    defp liquid_attribute(name, value, element, scope) do
      ~r/\{\{.*?\}\}/s
      |> Regex.split(value, include_captures: true, trim: true)
      |> Enum.reduce_while({:ok, []}, fn part, {:ok, parts} ->
        case attribute_part(part, element, scope) do
          {:ok, part} -> {:cont, {:ok, parts ++ [part]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, [{:expression, expression}]} -> {:ok, "#{name}={#{expression}}"}
        {:ok, parts} -> {:ok, "#{name}={\"#{Enum.map_join(parts, &interpolated/1)}\"}"}
        {:error, _reason} = error -> error
      end
    end

    defp attribute_part(part, element, scope) do
      case Regex.run(@output, part) do
        [_part, expression] ->
          with {:ok, expression} <- entry_expression(expression, part, scope), do: {:ok, {:expression, expression}}

        nil ->
          if String.contains?(part, ["{", "}"]),
            do: {:error, "a `{` or `}` in the attributes of a `<#{element}>`"},
            else: {:ok, {:text, part}}
      end
    end

    defp interpolated({:expression, expression}), do: "\#{" <> expression <> "}"

    defp interpolated({:text, text}),
      do: text |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"") |> String.replace("\#{", "\\\#{")

    # `entry.a.b` reads `@entry.a && @entry.a.b`: Liquid prints nothing for a
    # missing association, where HEEx would raise. A path an enclosing
    # `{% if %}` tested is not tested again, and `a[0]` reads `Enum.at(a, 0)`.
    defp entry_expression(expression, shown, scope) do
      with [_match, root, path] <- Regex.run(@liquid_path, String.trim(expression)),
           true <- root in scope.variables or (root == "entry" and path != "") do
        segments = Regex.scan(~r/\.([a-z_]\w*)(?:\[(\d+)\])?/, path, capture: :all_but_first)
        start = if root == "entry", do: {"entry", "@entry"}, else: {root, root}
        {reads, _last} = Enum.map_reduce(segments, start, &segment_read/2)
        {:ok, guarded(reads, root, scope)}
      else
        _ -> {:error, "the Liquid `#{shown}`"}
      end
    end

    defp segment_read([name], {liquid, code}), do: twice({"#{liquid}.#{name}", "#{code}.#{name}"})

    defp segment_read([name, index], {liquid, code}),
      do: twice({"#{liquid}.#{name}[#{index}]", "Enum.at(#{code}.#{name}, #{index})"})

    defp twice(read), do: {read, read}

    defp guarded([], root, _scope), do: root

    defp guarded(reads, _root, scope) do
      {tested, [last]} = Enum.split(reads, -1)

      tested
      |> Enum.reject(fn {liquid, _code} -> liquid in scope.tested end)
      |> Kernel.++([last])
      |> Enum.map_join(" && ", &elem(&1, 1))
    end

    ## Report

    defp add_notice(igniter, findings) do
      case Keyword.get_values(findings, :converted) do
        [] ->
          igniter

        converted ->
          Igniter.add_notice(igniter, """
          Legacy listing columns (`field`, `template`) became row components: a
          `component &__MODULE__.listing_row/1` in the listing and the
          `listing_row/1` it names at the end of the module (#{@guide}).
          Compare each listing with the old one:

          #{lines(converted)}
          #{section(findings, :language, """
          `field :language, :language` columns were dropped: a listing shows
          only entries in the editor's content language.
          """)}#{section(findings, :svg, """
          Inline `<svg>` icons in badges were dropped: 0.55's `.badge` puts an
          icon on a line of its own.
          """)}
          """)
      end
    end

    defp section(findings, kind, text) do
      case Keyword.get_values(findings, kind) do
        [] -> ""
        locations -> "\n#{text}\n#{lines(locations)}\n"
      end
    end

    defp add_warning(igniter, []), do: igniter

    defp add_warning(igniter, manual) do
      Igniter.add_warning(igniter, """
      Legacy listing columns (`field`, `template`) left as they are. They
      render nothing since 0.54. The task converts a listing only when it can
      convert every column; replace these listings' columns with a row
      component by hand (#{@guide}):

      #{lines(manual)}
      """)
    end

    defp lines(items), do: Enum.map_join(items, "\n", &("  " <> &1))
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.ListingRows do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
