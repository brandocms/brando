if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.BlueprintGettext do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # The admin translates a Blueprint's labels when it renders them, in the
    # schema's own Gettext domain, `<domain>_<schema>` (since 0.54; 0.53 used
    # one domain per context). `t/1` extracts a msgid into that domain;
    # `gettext/1` extracts it into `default`, where the admin never looks, so
    # such a label shows its msgid.
    #
    # `rewrite/1` turns `gettext("literal")` into `t("literal")` where the
    # admin translates the value through the schema domain: tab names, alert
    # texts, the `label`, `placeholder` and `instructions` of form entries and
    # of literal option maps, the labels of listing filters, actions,
    # selection actions, sorts and exports, an action's or selection
    # action's `confirm`, and `translate` values. Filter options and the
    # `blocks` label are shown as compiled, so they keep `gettext/1`.
    # Other Gettext calls in those places are listed.
    #
    # `carry_default_translations/1` then copies each `t/1` msgid's
    # translation from the `default` domain's catalog into the schema's, so
    # the merge keeps it.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Rewrite.Source
    alias Sourceror.Zipper

    @text_keys [:label, :placeholder, :instructions]
    @listing_labelled [:filter, :action, :selection_action, :sort, :export]
    @gettext_calls [:gettext, :ngettext, :pgettext, :pngettext]

    @doc """
    Rewrites literal `gettext/1` labels in Blueprint `forms`, `listings` and
    `translations` to `t/1`, and lists the Gettext calls there it leaves.
    """
    def rewrite(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)

      {igniter, rewritten, left} =
        Enum.reduce(blueprints, {igniter, [], []}, fn module, {igniter, rewritten, left} ->
          {igniter, count, path, found} = rewrite_blueprint(igniter, module)
          {igniter, rewritten ++ if(count == 0, do: [], else: [{path, count}]), left ++ found}
        end)

      igniter
      |> add_rewrite_notice(rewritten)
      |> add_rewrite_warning(left)
    end

    defp rewrite_blueprint(igniter, module) do
      {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
      path = Source.get(source, :path)
      {ast, {count, found}} = rewrite_module(Zipper.node(zipper), path)

      igniter =
        if count == 0,
          do: igniter,
          else: Igniter.update_elixir_file(igniter, path, fn _zipper -> {:ok, Zipper.replace(zipper, ast)} end)

      {igniter, count, path, found}
    end

    defp rewrite_module({:defmodule, meta, [alias, [{do_key, body}]]}, path) do
      {statements, acc} =
        body
        |> statements()
        |> Enum.map_reduce({0, []}, fn
          {section, _, [[{{:__block__, _, [:do]}, _}]]} = statement, acc
          when section in [:forms, :listings, :translations] ->
            Macro.prewalk(statement, acc, &rewrite_entry(&1, &2, section, path))

          statement, acc ->
            {statement, acc}
        end)

      {{:defmodule, meta, [alias, [{do_key, {:__block__, block_meta(body), statements}}]]}, acc}
    end

    defp rewrite_module(ast, _path), do: {ast, {0, []}}

    defp statements({:__block__, _, statements}) when is_list(statements), do: statements
    defp statements(statement), do: [statement]

    defp block_meta({:__block__, meta, statements}) when is_list(statements), do: meta
    defp block_meta(_statement), do: []

    defp rewrite_entry({:tab, _, [_name | _]} = node, acc, :forms, path), do: rewrite_args(node, [0], acc, path)

    defp rewrite_entry({:alert, _, [_type, _content | _]} = node, acc, :forms, path),
      do: rewrite_args(node, [1], acc, path)

    defp rewrite_entry({:blocks, _, _} = node, acc, :forms, _path), do: {node, acc}

    defp rewrite_entry({key, _, [_value]} = node, acc, section, path)
         when key in @text_keys and section in [:forms, :listings] do
      if key == :label or section == :forms, do: rewrite_args(node, [0], acc, path), else: {node, acc}
    end

    defp rewrite_entry({:%{}, meta, pairs}, acc, :forms, path) do
      {pairs, acc} = rewrite_keyword(pairs, [:label], acc, path)
      {{:%{}, meta, pairs}, acc}
    end

    defp rewrite_entry({name, _, [_ | _]} = node, acc, :forms, path) when is_atom(name),
      do: rewrite_options(node, @text_keys, acc, path)

    defp rewrite_entry({name, _, [_ | _]} = node, acc, :listings, path) when name in [:action, :selection_action],
      do: rewrite_options(node, [:label, :confirm], acc, path)

    defp rewrite_entry({name, _, [_ | _]} = node, acc, :listings, path) when name in @listing_labelled,
      do: rewrite_options(node, [:label], acc, path)

    defp rewrite_entry({:translate, _, [_key, _value]} = node, acc, :translations, path),
      do: rewrite_args(node, [1], acc, path)

    defp rewrite_entry(node, acc, _section, _path), do: {node, acc}

    defp rewrite_args({name, meta, args}, indexes, acc, path) do
      {args, acc} =
        args
        |> Enum.with_index()
        |> Enum.map_reduce(acc, fn {arg, index}, acc ->
          if index in indexes, do: rewrite_value(arg, acc, path), else: {arg, acc}
        end)

      {{name, meta, args}, acc}
    end

    # The keyword list a call ends with: `label: gettext("Name")`.
    defp rewrite_options({name, meta, args} = node, keys, acc, path) do
      case Enum.split(args, -1) do
        {arguments, [[{{:__block__, _, [key]}, _value} | _] = options]} when is_atom(key) ->
          {options, acc} = rewrite_keyword(options, keys, acc, path)
          {{name, meta, arguments ++ [options]}, acc}

        _other ->
          {node, acc}
      end
    end

    defp rewrite_keyword(pairs, keys, acc, path) do
      Enum.map_reduce(pairs, acc, fn
        {{:__block__, _, [key]} = key_ast, value}, acc when is_atom(key) ->
          if key in keys do
            {value, acc} = rewrite_value(value, acc, path)
            {{key_ast, value}, acc}
          else
            {{key_ast, value}, acc}
          end

        pair, acc ->
          {pair, acc}
      end)
    end

    defp rewrite_value({:gettext, meta, [{:__block__, _, [msgid]} = literal]}, {count, left}, _path)
         when is_binary(msgid),
         do: {{:t, meta, [literal]}, {count + 1, left}}

    defp rewrite_value({call, meta, args} = value, {count, left}, path) when call in @gettext_calls and is_list(args),
      do: {value, {count, left ++ ["#{path}:#{meta[:line]}: #{Sourceror.to_string(value)}"]}}

    defp rewrite_value(value, acc, _path), do: {value, acc}

    defp add_rewrite_notice(igniter, []), do: igniter

    defp add_rewrite_notice(igniter, rewritten) do
      Igniter.add_notice(igniter, """
      Blueprint labels written with `gettext/1` now use `t/1`. The admin
      translates them in the schema's own domain (`<domain>_<schema>`), where
      `gettext/1` never puts them, so they showed their msgid.
      `mix brando.migrate55` copies their translations from the `default`
      domain's catalogs:

      #{Enum.map_join(rewritten, "\n", fn {path, count} -> "  #{path} (#{count})" end)}
      """)
    end

    defp add_rewrite_warning(igniter, []), do: igniter

    defp add_rewrite_warning(igniter, left) do
      Igniter.add_warning(igniter, """
      Blueprint labels the admin translates in the schema's own domain, but
      written with a Gettext call `t/1` cannot replace (it takes one literal
      msgid). Rewrite each by hand, or the admin shows its msgid:

      #{Enum.map_join(left, "\n", &("  " <> &1))}
      """)
    end

    ## Catalogs

    @doc """
    Copies the translation of each `t/1` msgid in a Blueprint from the
    `default` domain's catalog into `<domain>_<schema>.po` beside it.

    A label written with `gettext/1` was translated in `default`;
    `rewrite/1` (in `mix brando.migrate54`, or by hand) moved it to `t/1`,
    which extracts into the schema's domain. Only `LC_MESSAGES` directories
    that already hold that domain (or its 0.53 context domains, or its `.pot`
    beside them) are written, and a translation the target has is never
    replaced.
    """
    def carry_default_translations(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)
      igniter = Igniter.include_glob(igniter, "priv/gettext/**/*.{po,pot}")

      msgids =
        blueprints
        |> Enum.map(fn module ->
          {:ok, {_igniter, _source, zipper}} = ProjectModule.find_module(igniter, module)
          {catalog_domain(zipper), t_msgids(Zipper.node(zipper))}
        end)
        |> Enum.reject(fn {domain, msgids} -> is_nil(domain) or msgids == [] end)
        |> Enum.reduce(%{}, fn {domain, msgids}, acc -> Map.update(acc, domain, msgids, &Enum.uniq(&1 ++ msgids)) end)

      paths = igniter.rewrite |> Rewrite.sources() |> Enum.map(&Source.get(&1, :path))

      for path <- paths,
          Path.basename(path) == "default.po" and Path.basename(Path.dirname(path)) == "LC_MESSAGES",
          {domain, domain_msgids} <- msgids,
          domain_catalog?(paths, path, domain),
          reduce: igniter do
        igniter -> carry(igniter, path, Path.join(Path.dirname(path), domain <> ".po"), domain_msgids)
      end
    end

    defp catalog_domain(zipper) do
      with {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, use_zipper} <- Igniter.Code.Module.move_to_use(body, Brando.Blueprint),
           {:ok, options} <- CodeFunction.move_to_nth_argument(use_zipper, 1),
           {:ok, domain} <- literal_option(options, :domain),
           {:ok, schema} <- literal_option(options, :schema) do
        String.downcase("#{domain}_#{schema}")
      else
        _ -> nil
      end
    end

    defp literal_option(options, key) do
      with {:ok, value} <- Igniter.Code.Keyword.get_key(options, key),
           {:__block__, _, [string]} when is_binary(string) <- Zipper.node(value) do
        {:ok, string}
      else
        _ -> :error
      end
    end

    defp t_msgids(ast) do
      {_ast, msgids} =
        Macro.prewalk(ast, [], fn
          {:t, _, [{:__block__, _, [msgid]}]} = node, acc when is_binary(msgid) -> {node, [msgid | acc]}
          node, acc -> {node, acc}
        end)

      msgids |> Enum.reverse() |> Enum.uniq()
    end

    # The backend directory of `default.po` holds the domain when it has its
    # catalog, a 0.53 context catalog, or a `.pot` for either.
    defp domain_catalog?(paths, default_po, domain) do
      locale_dir = Path.dirname(default_po)
      backend_dir = locale_dir |> Path.dirname() |> Path.dirname()

      Enum.any?(paths, fn path ->
        Path.dirname(path) in [locale_dir, backend_dir] and
          Path.rootname(Path.basename(path)) in [domain | Enum.map(~w(naming forms listings), &"#{domain}_#{&1}")]
      end)
    end

    defp carry(igniter, default_path, target, msgids) do
      exists? = Igniter.exists?(igniter, target)

      with {:ok, default} <- parse(igniter, default_path),
           {:ok, catalog} <- if(exists?, do: parse(igniter, target), else: {:ok, %{default | messages: []}}),
           translations = default_translations(default, msgids),
           messages = Enum.reduce(msgids, catalog.messages, &put_translation(&2, &1, translations)),
           true <- messages != catalog.messages do
        content = %{catalog | messages: messages} |> Expo.PO.compose() |> IO.iodata_to_binary()

        if exists?,
          do: Igniter.update_file(igniter, target, &Source.update(&1, :content, content)),
          else: Igniter.create_new_file(igniter, target, content)
      else
        _ -> igniter
      end
    end

    defp parse(igniter, path) do
      igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content) |> Expo.PO.parse_string()
    end

    defp default_translations(catalog, msgids) do
      for %Expo.Message.Singular{msgctxt: nil} = message <- catalog.messages,
          msgid = IO.iodata_to_binary(message.msgid),
          msgid in msgids,
          IO.iodata_to_binary(message.msgstr) != "",
          into: %{},
          do: {msgid, %{message | references: [], extracted_comments: []}}
    end

    defp put_translation(messages, msgid, translations) do
      case Map.fetch(translations, msgid) do
        {:ok, translated} ->
          case Enum.find_index(messages, &Expo.Message.same?(&1, translated)) do
            nil -> messages ++ [translated]
            index -> List.update_at(messages, index, &fill(&1, translated))
          end

        :error ->
          messages
      end
    end

    defp fill(%Expo.Message.Singular{msgstr: msgstr} = message, translated) do
      if IO.iodata_to_binary(msgstr) == "", do: %{message | msgstr: translated.msgstr}, else: message
    end

    defp fill(message, _translated), do: message
  end
end
