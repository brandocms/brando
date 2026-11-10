if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.AIDependency do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    # Brando's AI features need `req_llm`, which Brando no longer brings in.
    # An upgrade adds it to an application whose config sets AI up, with the
    # settings `Brando.AI.settings/0` counts for the doctor and the boot log,
    # read from source: the application's config may not evaluate yet.

    alias Mix.Brando.Igniter.Dependencies

    # The configuration a release or a development server reads, in the
    # order it applies: the base, the environment's file, then runtime.exs.
    # test.exs is left out: it points the client at cassettes, no AI of its own.
    @base "config/config.exs"
    @environments ~w(config/dev.exs config/prod.exs)
    @runtime "config/runtime.exs"

    @ai_keys [:models, :default_model, :providers, :prompts, :fields]

    @doc """
    Adds `Brando.AI.dependency/0` when the application configures AI and has
    no `req_llm`, with a notice naming the settings found. Leaves `mix.exs`
    as it is otherwise, whatever form a `req_llm` it has takes.
    """
    def plan(igniter) do
      {igniter, read} =
        Enum.reduce([@base, @runtime | @environments], {igniter, %{}}, fn root, {igniter, read} ->
          {igniter, events, _seen} = events(igniter, root, MapSet.new())
          {igniter, Map.put(read, root, events)}
        end)

      found =
        @environments
        |> Enum.flat_map(&ai_settings(read[@base] ++ read[&1] ++ read[@runtime]))
        |> Enum.uniq()

      case found do
        [] ->
          igniter

        found ->
          # Not has_dep?/2: it reads a deps/0 Igniter cannot place as no req_llm,
          # and adding to it then fails the whole upgrade.
          case Igniter.Project.Deps.get_dep(igniter, :req_llm) do
            {:ok, nil} -> igniter |> Dependencies.add_new(Brando.AI.dependency()) |> added(found)
            {:ok, _declared} -> igniter
            _unreadable -> by_hand(igniter, found)
          end
      end
    end

    # One environment's settings, from `events` in the order its config
    # applies them: none when the last `enabled:` set is a literal false or
    # nil, as in the merged config the doctor reads. An `enabled:` it cannot
    # read is on, and so is one under a condition (runtime.exs's
    # `config_env()` branches): runtime.exs applies to both environments.
    defp ai_settings(events) do
      # The default, when no file sets it, is on.
      enabled = for {:enabled, value} <- events, do: value

      case List.last([true | enabled]) do
        off when off in [false, nil] -> []
        _on -> for {:setting, name} <- events, do: name
      end
    end

    defp added(igniter, found) do
      Igniter.add_notice(igniter, """
      Added #{inspect(Brando.AI.dependency())} to mix.exs: the application configures AI
      (#{Enum.join(found, ", ")}), and Brando's AI features (AI actions, alt text drafts,
      the content assistant) call models through req_llm, which Brando no longer brings in.
      Without it they would turn off. mix deps.get fetches it.
      """)
    end

    defp by_hand(igniter, found) do
      Igniter.add_notice(igniter, """
      The application configures AI (#{Enum.join(found, ", ")}), and Brando's AI features
      need req_llm, which Brando no longer brings in. Its deps/0 in mix.exs is not one list,
      so the upgrade left it as it is: add #{inspect(Brando.AI.dependency())} unless it has it.
      """)
    end

    # The `{:setting, name}` and `{:enabled, value}` events of `path` in source
    # order, with each literal import_config's events in its place, as Config
    # applies them. A file is read once per root, which also stops cycles.
    defp events(igniter, path, seen) do
      if path in seen or not Igniter.exists?(igniter, path) do
        {igniter, [], MapSet.put(seen, path)}
      else
        seen = MapSet.put(seen, path)

        case include(igniter, path) do
          {:ok, igniter, quoted} ->
            quoted
            |> scan(path)
            |> Enum.reduce({igniter, [], seen}, fn
              {:import, file}, {igniter, acc, seen} ->
                {igniter, imported, seen} = events(igniter, file, seen)
                {igniter, Enum.reverse(imported, acc), seen}

              event, {igniter, acc, seen} ->
                {igniter, [event | acc], seen}
            end)
            |> then(fn {igniter, acc, seen} -> {igniter, Enum.reverse(acc), seen} end)

          # A file that does not parse sets nothing here; the upgrade goes on.
          :error ->
            {igniter, [], seen}
        end
      end
    end

    # Igniter parses a source as it includes it, and raises on a syntax error.
    defp include(igniter, path) do
      igniter = Igniter.include_existing_file(igniter, path)
      content = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

      case Code.string_to_quoted(content) do
        {:ok, quoted} -> {:ok, igniter, quoted}
        {:error, _} -> :error
      end
    rescue
      _ in [SyntaxError, TokenMissingError, MismatchedDelimiterError] -> :error
    end

    @conditionals [:if, :unless, :case, :cond, :with]

    # This file's events in source order, imports as `{:import, path}`. An
    # `enabled:` under a condition is `:conditional`: it may not apply.
    defp scan(quoted, path, conditional? \\ false) do
      {_, events} =
        Macro.prewalk(quoted, [], fn
          {kind, _, args}, events when kind in @conditionals and is_list(args) ->
            # Scanned here, flagged; the walk does not go into it again.
            {:conditional, Enum.reverse(scan(args, path, true), events)}

          {:config, _, [:brando, {:__aliases__, _, [:Brando, :AI]}, opts]} = node, events when is_list(opts) ->
            {node, Enum.reverse(brando_ai(opts, conditional?), events)}

          {:config, _, [:brando, {:__aliases__, _, [:Brando, :AI, :Agent]}, opts]} = node, events when is_list(opts) ->
            {node, if(present?(opts[:model]), do: [{:setting, "Brando.AI.Agent model"} | events], else: events)}

          {:config, _, [:req_llm, opts]} = node, events when is_list(opts) ->
            {node, if(api_keys?(opts), do: [{:setting, "req_llm API keys"} | events], else: events)}

          {:config, _, [:req_llm, key, value]} = node, events when is_atom(key) ->
            {node, if(api_keys?([{key, value}]), do: [{:setting, "req_llm API keys"} | events], else: events)}

          {:import_config, _, [import]} = node, events when is_binary(import) ->
            file = import |> Path.expand(Path.dirname(Path.expand(path))) |> Path.relative_to_cwd()
            {node, [{:import, file} | events]}

          node, events ->
            {node, events}
        end)

      Enum.reverse(events)
    end

    defp brando_ai(opts, conditional?) do
      settings =
        for {key, value} <- opts,
            is_atom(key),
            key in @ai_keys or String.ends_with?(Atom.to_string(key), "_api_key"),
            present?(value),
            do: {:setting, setting(key)}

      cond do
        not Keyword.has_key?(opts, :enabled) -> settings
        conditional? -> settings ++ [{:enabled, :conditional}]
        true -> settings ++ [{:enabled, opts[:enabled]}]
      end
    end

    defp setting(key) when key in [:models, :default_model], do: "Brando.AI models"
    defp setting(key) when key in [:prompts, :fields], do: "Brando.AI prompts"
    defp setting(_providers_or_key), do: "Brando.AI providers"

    defp api_keys?(opts) do
      Enum.any?(opts, fn
        {key, value} when is_atom(key) -> String.ends_with?(Atom.to_string(key), "_api_key") and present?(value)
        _ -> false
      end)
    end

    # A literal that sets nothing; anything else, a System.get_env/1 call
    # included, is a setting.
    defp present?(value), do: value not in [nil, "", []] and not match?({:%{}, _, []}, value)
  end
else
  defmodule Mix.Brando.Igniter.AIDependency do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
