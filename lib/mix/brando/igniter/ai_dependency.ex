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
      {igniter, found} = settings(igniter, @configs, MapSet.new(), [])

      cond do
        found == [] -> igniter
        Igniter.Project.Deps.has_dep?(igniter, :req_llm) -> igniter
        true -> igniter |> Dependencies.add_new(Brando.AI.dependency()) |> notice(found)
      end
    end

    defp notice(igniter, found) do
      Igniter.add_notice(igniter, """
      Added #{inspect(Brando.AI.dependency())} to mix.exs: the application configures AI
      (#{found |> Enum.reverse() |> Enum.uniq() |> Enum.join(", ")}), and Brando's AI features
      (AI actions, alt text drafts, the content assistant) call models through req_llm,
      which Brando no longer brings in. Without it they would turn off. mix deps.get fetches it.
      """)
    end

    # The settings in `paths` and the files they import, each read once.
    defp settings(igniter, [], _seen, found), do: {igniter, found}

    defp settings(igniter, [path | paths], seen, found) do
      if path in seen or not Igniter.exists?(igniter, path) do
        settings(igniter, paths, MapSet.put(seen, path), found)
      else
        igniter = Igniter.include_existing_file(igniter, path)
        content = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

        {in_file, imports} =
          case Code.string_to_quoted(content) do
            {:ok, quoted} -> scan(quoted, path)
            {:error, _} -> {[], []}
          end

        settings(igniter, paths ++ imports, MapSet.put(seen, path), in_file ++ found)
      end
    end

    defp scan(quoted, path) do
      {_, {found, imports, disabled}} =
        Macro.prewalk(quoted, {[], [], []}, fn
          {:config, _, [:brando, {:__aliases__, _, [:Brando, :AI]}, opts]} = node, acc when is_list(opts) ->
            {node, brando_ai(opts, acc)}

          {:config, _, [:brando, {:__aliases__, _, [:Brando, :AI, :Agent]}, opts]} = node, {found, imports, disabled}
          when is_list(opts) ->
            found = if present?(opts[:model]), do: ["Brando.AI.Agent model" | found], else: found
            {node, {found, imports, disabled}}

          {:config, _, [:req_llm, opts]} = node, {found, imports, disabled} when is_list(opts) ->
            found = if api_keys?(opts), do: ["req_llm API keys" | found], else: found
            {node, {found, imports, disabled}}

          {:config, _, [:req_llm, key, value]} = node, {found, imports, disabled} when is_atom(key) ->
            found = if api_keys?([{key, value}]), do: ["req_llm API keys" | found], else: found
            {node, {found, imports, disabled}}

          {:import_config, _, [import]} = node, {found, imports, disabled} when is_binary(import) ->
            file = import |> Path.expand(Path.dirname(Path.expand(path))) |> Path.relative_to_cwd()
            {node, {found, [file | imports], disabled}}

          node, acc ->
            {node, acc}
        end)

      # `enabled: false` in the same file turns the settings beside it off, as
      # it does for the doctor; an `enabled:` it cannot read leaves them on.
      found = if disabled != [] and Enum.all?(disabled, &(&1 == false)), do: [], else: found
      {found, Enum.reverse(imports)}
    end

    defp brando_ai(opts, {found, imports, disabled}) do
      named =
        for {key, value} <- opts,
            is_atom(key),
            key in @ai_keys or String.ends_with?(Atom.to_string(key), "_api_key"),
            present?(value),
            do: setting(key)

      disabled = if Keyword.has_key?(opts, :enabled), do: [opts[:enabled] | disabled], else: disabled
      {named ++ found, imports, disabled}
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
