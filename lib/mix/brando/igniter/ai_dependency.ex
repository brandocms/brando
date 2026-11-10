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

    # The configuration a release or a development server reads. test.exs is
    # left out: it points the client at cassettes, which is no AI of its own.
    @configs ~w(config/config.exs config/dev.exs config/prod.exs config/runtime.exs)

    @ai_keys [:models, :default_model, :providers, :prompts, :fields]

    @doc """
    Adds `Brando.AI.dependency/0` when the application configures AI and has
    no `req_llm`, with a notice naming the settings found. Leaves `mix.exs`
    as it is otherwise, whatever form a `req_llm` it has takes.
    """
    def plan(igniter) do
      {igniter, files} = settings(igniter, @configs, MapSet.new(), [])

      case ai_settings(files) do
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

    # Settings count unless every `enabled:` the files set is a literal false,
    # which turns AI off wherever the settings are (the doctor reads the
    # merged config the same way). An `enabled:` it cannot read leaves AI on.
    defp ai_settings(files) do
      enabled = Enum.flat_map(files, fn {_found, enabled} -> enabled end)

      if enabled != [] and Enum.all?(enabled, &(&1 == false)),
        do: [],
        else: files |> Enum.flat_map(fn {found, _enabled} -> found end) |> Enum.uniq()
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

    # `{settings, enabled values}` of each file in `paths` and the files they
    # import, each read once.
    defp settings(igniter, [], _seen, files), do: {igniter, Enum.reverse(files)}

    defp settings(igniter, [path | paths], seen, files) do
      if path in seen or not Igniter.exists?(igniter, path) do
        settings(igniter, paths, MapSet.put(seen, path), files)
      else
        case include(igniter, path) do
          {:ok, igniter, quoted} ->
            {file, imports} = scan(quoted, path)
            settings(igniter, paths ++ imports, MapSet.put(seen, path), [file | files])

          # A file that does not parse sets nothing here; the upgrade goes on.
          :error ->
            settings(igniter, paths, MapSet.put(seen, path), files)
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

    defp scan(quoted, path) do
      {_, {found, imports, enabled}} =
        Macro.prewalk(quoted, {[], [], []}, fn
          {:config, _, [:brando, {:__aliases__, _, [:Brando, :AI]}, opts]} = node, acc when is_list(opts) ->
            {node, brando_ai(opts, acc)}

          {:config, _, [:brando, {:__aliases__, _, [:Brando, :AI, :Agent]}, opts]} = node, {found, imports, enabled}
          when is_list(opts) ->
            found = if present?(opts[:model]), do: ["Brando.AI.Agent model" | found], else: found
            {node, {found, imports, enabled}}

          {:config, _, [:req_llm, opts]} = node, {found, imports, enabled} when is_list(opts) ->
            found = if api_keys?(opts), do: ["req_llm API keys" | found], else: found
            {node, {found, imports, enabled}}

          {:config, _, [:req_llm, key, value]} = node, {found, imports, enabled} when is_atom(key) ->
            found = if api_keys?([{key, value}]), do: ["req_llm API keys" | found], else: found
            {node, {found, imports, enabled}}

          {:import_config, _, [import]} = node, {found, imports, enabled} when is_binary(import) ->
            file = import |> Path.expand(Path.dirname(Path.expand(path))) |> Path.relative_to_cwd()
            {node, {found, [file | imports], enabled}}

          node, acc ->
            {node, acc}
        end)

      {{Enum.reverse(found), enabled}, Enum.reverse(imports)}
    end

    defp brando_ai(opts, {found, imports, enabled}) do
      named =
        for {key, value} <- opts,
            is_atom(key),
            key in @ai_keys or String.ends_with?(Atom.to_string(key), "_api_key"),
            present?(value),
            do: setting(key)

      enabled = if Keyword.has_key?(opts, :enabled), do: [opts[:enabled] | enabled], else: enabled
      {named ++ found, imports, enabled}
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
