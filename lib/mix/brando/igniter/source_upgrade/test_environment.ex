if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.TestEnvironment do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Warns about test setup that makes `mix test` unsafe or unrunnable after
    # an upgrade: a Repo URL that `config/runtime.exs` reads from the shell in
    # every environment, and `test_paths` that name missing directories.
    # Warning only: the right guard depends on how the site is deployed.

    alias Rewrite.Source

    @runtime "config/runtime.exs"
    @env_reads [:get_env, :fetch_env, :fetch_env!]

    @doc "Adds a warning for each hazard found."
    def warn_test_hazards(igniter) do
      igniter
      |> warn_runtime_repo_url()
      |> warn_missing_test_paths()
    end

    ## config/runtime.exs

    defp warn_runtime_repo_url(igniter) do
      with true <- Igniter.exists?(igniter, @runtime),
           igniter = Igniter.include_existing_file(igniter, @runtime),
           content = source_content(igniter, @runtime),
           {:ok, ast} <- Code.string_to_quoted(content),
           [_ | _] = findings <- repo_url_reads(ast) do
        lines = String.split(content, "\n")

        shown =
          Enum.map_join(findings, "\n", fn {line, variable} ->
            "  #{@runtime}:#{line}: #{lines |> Enum.at(line - 1, "") |> String.trim()}#{variable_note(variable)}"
          end)

        Igniter.add_warning(igniter, """
        `config/runtime.exs` reads the Repo's `url:` from the environment in every
        environment, `:test` included:

        #{shown}

        `mix test` then uses whatever database that variable names in your shell, not
        the test database in `config/test.exs`. On a development machine that is the
        development database (or a production copy), and a `test` alias that runs
        `ecto.create` and `ecto.migrate` migrates it. Read the URL only outside tests:

            if config_env() != :test do
              config :my_app, MyApp.Repo, url: System.get_env("DATABASE_URL")
            end
        """)
      else
        _ -> igniter
      end
    end

    defp variable_note(nil), do: ""
    defp variable_note(name), do: " (#{name})"

    # `[{line, env_variable_name}]` for `config _, *Repo, url: <env read>`
    # calls `mix test` evaluates.
    defp repo_url_reads(ast) do
      env_bound = env_bound_variables(ast)
      ast |> collect(true, env_bound, []) |> Enum.reverse()
    end

    defp collect({:if, _, [condition, branches]}, reachable?, env_bound, acc) when is_list(branches),
      do: collect_branches(test_value(condition), branches, reachable?, env_bound, acc)

    defp collect({:unless, _, [condition, branches]}, reachable?, env_bound, acc) when is_list(branches) do
      value =
        case test_value(condition) do
          {:ok, value} -> {:ok, not value}
          :unknown -> :unknown
        end

      collect_branches(value, branches, reachable?, env_bound, acc)
    end

    defp collect(
           {:case, meta, [{{:., _, [{:__aliases__, _, [:Config]}, :config_env]}, _, []}, body]},
           reachable?,
           env_bound,
           acc
         ),
         do: collect({:case, meta, [{:config_env, [], []}, body]}, reachable?, env_bound, acc)

    defp collect({:case, _, [{:config_env, _, []}, [do: clauses]]}, reachable?, env_bound, acc) do
      Enum.reduce(clauses, acc, fn {:->, _, [[pattern], body]}, acc ->
        collect(body, reachable? and test_pattern?(pattern), env_bound, acc)
      end)
    end

    defp collect({:config, meta, [_app, {:__aliases__, _, alias}, opts]} = _call, true, env_bound, acc)
         when is_list(opts) do
      with true <- alias |> List.last() |> Atom.to_string() |> String.ends_with?("Repo"),
           {:ok, url} <- Keyword.fetch(opts, :url),
           {:ok, variable} <- env_read(url, env_bound) do
        [{meta[:line], variable} | acc]
      else
        _ -> acc
      end
    end

    defp collect({_name, _meta, args}, reachable?, env_bound, acc) when is_list(args),
      do: Enum.reduce(args, acc, &collect(&1, reachable?, env_bound, &2))

    defp collect({left, right}, reachable?, env_bound, acc),
      do: collect(right, reachable?, env_bound, collect(left, reachable?, env_bound, acc))

    defp collect(list, reachable?, env_bound, acc) when is_list(list),
      do: Enum.reduce(list, acc, &collect(&1, reachable?, env_bound, &2))

    defp collect(_other, _reachable?, _env_bound, acc), do: acc

    defp collect_branches(value, branches, reachable?, env_bound, acc) do
      acc = collect(Keyword.get(branches, :do), reachable? and value != {:ok, false}, env_bound, acc)
      collect(Keyword.get(branches, :else), reachable? and value != {:ok, true}, env_bound, acc)
    end

    defp test_pattern?(:test), do: true
    defp test_pattern?({name, _, context}) when is_atom(name) and is_atom(context), do: true
    defp test_pattern?({:when, _, [pattern, _guard]}), do: test_pattern?(pattern)
    defp test_pattern?(_pattern), do: false

    # Evaluates a condition on `config_env()` for `:test`, from literals and
    # comparison and boolean operators only.
    defp test_value({:config_env, _, []}), do: {:ok, :test}
    defp test_value({{:., _, [{:__aliases__, _, [:Config]}, :config_env]}, _, []}), do: {:ok, :test}
    defp test_value(value) when is_atom(value) or is_binary(value) or is_number(value), do: {:ok, value}

    defp test_value(list) when is_list(list) do
      Enum.reduce_while(list, {:ok, []}, fn item, {:ok, values} ->
        case test_value(item) do
          {:ok, value} -> {:cont, {:ok, values ++ [value]}}
          :unknown -> {:halt, :unknown}
        end
      end)
    end

    defp test_value({operator, _, [left, right]}) when operator in [:==, :!=, :===, :!==, :in, :and, :or, :&&, :||] do
      with {:ok, left} <- test_value(left), {:ok, right} <- test_value(right) do
        {:ok, apply_operator(operator, left, right)}
      end
    end

    defp test_value({operator, _, [value]}) when operator in [:not, :!] do
      with {:ok, value} <- test_value(value), do: {:ok, not value}
    end

    defp test_value(_condition), do: :unknown

    defp apply_operator(:in, left, right) when is_list(right), do: left in right
    defp apply_operator(operator, left, right) when operator in [:==, :===], do: left == right
    defp apply_operator(operator, left, right) when operator in [:!=, :!==], do: left != right
    defp apply_operator(operator, left, right) when operator in [:and, :&&], do: left == true and right == true
    defp apply_operator(operator, left, right) when operator in [:or, :||], do: left == true or right == true

    # `{:ok, "VAR" | nil}` when `ast` reads the environment, directly or
    # through a variable bound to such a read.
    defp env_read({name, _, context}, env_bound) when is_atom(name) and is_atom(context),
      do: Map.fetch(env_bound, name)

    defp env_read(ast, _env_bound) do
      {_ast, found} =
        Macro.prewalk(ast, nil, fn
          {{:., _, [{:__aliases__, _, [:System]}, function]}, _, args} = node, nil when function in @env_reads ->
            {node, {:ok, env_name(args)}}

          node, found ->
            {node, found}
        end)

      found || :error
    end

    defp env_name([name | _]) when is_binary(name), do: name
    defp env_name(_args), do: nil

    defp env_bound_variables(ast) do
      {_ast, bound} =
        Macro.prewalk(ast, %{}, fn
          {:=, _, [{name, _, context}, value]} = node, bound when is_atom(name) and is_atom(context) ->
            case env_read(value, %{}) do
              {:ok, variable} -> {node, Map.put(bound, name, variable)}
              :error -> {node, bound}
            end

          node, bound ->
            {node, bound}
        end)

      bound
    end

    ## mix.exs test_paths

    defp warn_missing_test_paths(igniter) do
      with true <- Igniter.exists?(igniter, "mix.exs"),
           igniter = Igniter.include_existing_file(igniter, "mix.exs"),
           content = source_content(igniter, "mix.exs"),
           {:ok, ast} <- Code.string_to_quoted(content),
           {:ok, line, paths} <- test_paths(ast, content),
           [_ | _] = missing <- Enum.reject(paths, &directory?(igniter, &1)) do
        Igniter.add_warning(igniter, """
        `test_paths` in mix.exs:#{line} names directories that do not exist: #{Enum.map_join(missing, ", ", &"`#{&1}`")}.
        `mix test` stops with "Cannot run tests because test helper file
        "#{hd(missing)}/test_helper.exs" does not exist". Point `test_paths` at the
        directory that holds `test_helper.exs`, usually `["test"]`.
        """)
      else
        _ -> igniter
      end
    end

    # `{:ok, line, paths}` that `mix test` runs in `:test`.
    defp test_paths(ast, content) do
      with {:ok, project} <- project_keywords(ast),
           {:ok, value} <- Keyword.fetch(project, :test_paths) do
        test_paths_value(value, ast, content)
      else
        _ -> :error
      end
    end

    # A literal list carries no line of its own: it is the `test_paths:` line.
    defp test_paths_value(value, _ast, content) when is_list(value) do
      line = content |> String.split("\n") |> Enum.find_index(&(&1 =~ ~r/\btest_paths:/))

      if Enum.all?(value, &is_binary/1) and line, do: {:ok, line + 1, value}, else: :error
    end

    defp test_paths_value({name, _, [_env]}, ast, _content) when is_atom(name) do
      ast
      |> function_clauses(name)
      |> Enum.find(fn {pattern, guard?, _line, _body} -> not guard? and test_pattern?(pattern) end)
      |> case do
        {_pattern, _guard?, line, body} when is_list(body) ->
          if Enum.all?(body, &is_binary/1), do: {:ok, line, body}, else: :error

        _ ->
          :error
      end
    end

    defp test_paths_value(_value, _ast, _content), do: :error

    defp project_keywords(ast) do
      {_ast, found} =
        Macro.prewalk(ast, :error, fn
          {:def, _, [{:project, _, args}, [do: body]]} = node, :error when args in [nil, []] and is_list(body) ->
            {node, {:ok, body}}

          node, found ->
            {node, found}
        end)

      found
    end

    # `[{pattern, guard?, line, body}]` of the one-argument clauses of `name`.
    defp function_clauses(ast, name) do
      {_ast, clauses} =
        Macro.prewalk(ast, [], fn
          {kind, meta, [head, [do: body]]} = node, clauses when kind in [:def, :defp] ->
            case head do
              {:when, _, [{^name, _, [pattern]}, _guard]} -> {node, clauses ++ [{pattern, true, meta[:line], body}]}
              {^name, _, [pattern]} -> {node, clauses ++ [{pattern, false, meta[:line], body}]}
              _ -> {node, clauses}
            end

          node, clauses ->
            {node, clauses}
        end)

      clauses
    end

    defp directory?(igniter, path) do
      if igniter.assigns[:test_mode?] do
        prefix = String.trim_trailing(path, "/") <> "/"
        igniter.assigns |> Map.get(:test_files, %{}) |> Map.keys() |> Enum.any?(&String.starts_with?(&1, prefix))
      else
        File.dir?(path)
      end
    end

    defp source_content(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.TestEnvironment do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
