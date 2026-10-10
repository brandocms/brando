defmodule Brando.Credo.Check.TestSandboxShared do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["test/**/*.ex", "test/**/*.exs", "e2e/test/**/*.ex", "e2e/test/**/*.exs"]},
      allowed: %{}
    ],
    explanations: [
      check: """
      A test does not put the database sandbox in shared mode outside the
      allowlist.

      Shared mode (`Sandbox.mode(repo, {:shared, pid})`, or
      `Sandbox.start_owner!(repo, shared: ...)`) hands the test's connection
      to every process in the VM, including processes an earlier test left
      running. One such process, a presence tracker, wrote to `users` on the
      shared connection, held the lock, and stalled StructureCloner's
      integration setup for 15 s, failing 1,135 tests after it (#3119).

      Check out an unshared connection (`Sandbox.start_owner!/1`) and
      `Sandbox.allow/3` the processes that need it. Shared mode is acceptable
      only in a case template for `async: false` tests whose processes the
      test cannot name (LiveView, channel and endpoint processes); list such
      files under `allowed` in `.credo.exs`, each with a one-line reason.

      An allowlisted file that no longer uses shared mode is flagged too, so
      the list stays the inventory.
      """,
      params: [
        allowed: "A map of file paths, relative to the project root, to the reason the file may use shared mode."
      ]
    ]

  alias Brando.Credo.Aliases
  alias Credo.SourceFile

  @sandbox [:Ecto, :Adapters, :SQL, :Sandbox]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    ast = SourceFile.ast(source_file)
    uses = shared_uses(ast, Aliases.collect(ast))
    path = Path.relative_to_cwd(source_file.filename)
    allowed? = params |> Params.get(:allowed, __MODULE__) |> Map.get(path) |> reason?()

    case {uses, allowed?} do
      {[], false} -> []
      {[], true} -> [stale_issue(ctx, path)]
      {uses, false} -> Enum.map(uses, &issue_for(ctx, &1))
      {_uses, true} -> []
    end
  end

  defp reason?(reason) when is_binary(reason), do: String.trim(reason) != ""
  defp reason?(_reason), do: false

  defp shared_uses(ast, aliases) do
    {_ast, uses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case shared_use(node, aliases) do
          nil -> {node, acc}
          use -> {node, [use | acc]}
        end
      end)

    Enum.reverse(uses)
  end

  # The mode or options are the last argument, also when the repo is piped in.
  defp shared_use({{:., _, [{:__aliases__, meta, parts}, fun]}, _, [_ | _] = args}, aliases)
       when fun in [:mode, :start_owner!] do
    if Aliases.expand(parts, aliases) == @sandbox and shared?(fun, List.last(args)) do
      %{trigger: Enum.join(parts, ".") <> ".#{fun}", line: meta[:line], column: meta[:column]}
    end
  end

  defp shared_use(_node, _aliases), do: nil

  defp shared?(:mode, {:shared, _owner}), do: true

  defp shared?(:start_owner!, opts) when is_list(opts),
    do: Enum.any?(opts, &match?({:shared, value} when value != false, &1))

  defp shared?(_fun, _arg), do: false

  defp issue_for(ctx, use) do
    format_issue(
      ctx,
      message:
        "Shared sandbox mode lends this connection to every process, a previous test's leftovers included: " <>
          "start an unshared owner and `Sandbox.allow/3` the processes that need it, " <>
          "or list this file under `allowed` in .credo.exs with a reason.",
      trigger: use.trigger,
      line_no: use.line,
      column: use.column
    )
  end

  defp stale_issue(ctx, path) do
    format_issue(
      ctx,
      message: "#{path} no longer uses shared sandbox mode: remove it from `allowed` in .credo.exs.",
      line_no: 1
    )
  end
end
