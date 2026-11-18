defmodule Brando.Villain.RenderFailures do
  @moduledoc false
  # Collects the block templates that fail while blocks render, for
  # `Brando.Villain.parse_checked/3`. Only a render that collects changes
  # anything: a template error is recorded (`record/3`) with the block it
  # belongs to (`with_block/3`), and an exception a template raises is recorded
  # rather than raised (`guard/3`, and Liquex's in `Brando.Villain`), so every
  # failing block is named. Outside one, rendering logs, prints its error marks
  # and raises as it always has: what the live preview and the editor show.
  #
  # The state is the process's, as `Brando.Villain.RenderScope`'s: a render
  # runs in one process, nested renders (footnotes, a block's own render)
  # included.

  alias Brando.Villain.RenderFailure

  @failures {__MODULE__, :failures}
  @blocks {__MODULE__, :blocks}

  # Errors of the database, not of a template: raised, so the job retries
  @transient [DBConnection.ConnectionError, DBConnection.OwnershipError, Postgrex.Error]

  @doc """
  Runs `fun`, collecting the failures it records. Returns `{result, failures}`,
  in the order they were recorded. Within another collection they are
  collected there too, unless `merge: false`.
  """
  @spec collect((-> term), keyword) :: {term, [RenderFailure.t()]}
  def collect(fun, opts \\ []) do
    outer = Process.get(@failures)
    Process.put(@failures, [])

    try do
      result = fun.()
      {result, @failures |> Process.get() |> Enum.reverse()}
    after
      case outer do
        nil ->
          Process.delete(@failures)
          Process.delete(@blocks)

        outer ->
          inner = if Keyword.get(opts, :merge, true), do: Process.get(@failures), else: []
          Process.put(@failures, inner ++ outer)
      end
    end
  end

  @doc "Whether the render collects failures, rather than raising and logging them."
  @spec collecting?() :: boolean
  def collecting?, do: Process.get(@failures) != nil

  @doc "Adds failures recorded elsewhere (`collect(fun, merge: false)`)."
  @spec add([RenderFailure.t()]) :: :ok
  def add(failures) do
    if collecting?(), do: Process.put(@failures, Enum.reverse(failures) ++ Process.get(@failures))
    :ok
  end

  @doc """
  Runs `fun` as the render of `block`: a failure recorded within it names the
  block, unless a block rendered inside it is the one that failed. `opts` are
  the render's options, whose `:modules` name the block's module.
  """
  @spec with_block(map, map, (-> result)) :: result when result: term
  def with_block(block, opts, fun) do
    case Process.get(@failures) do
      nil ->
        fun.()

      _collecting ->
        blocks = Process.get(@blocks, [])
        Process.put(@blocks, [{block, opts[:modules]} | blocks])

        try do
          fun.()
        after
          Process.put(@blocks, blocks)
        end
    end
  end

  @doc "Records a failure of the template of the block rendering now, if the render collects them."
  @spec record(RenderFailure.kind(), String.t(), pos_integer | nil) :: :ok
  def record(kind, message, line \\ nil) do
    case Process.get(@failures) do
      nil ->
        :ok

      failures ->
        failure = put_block(%RenderFailure{kind: kind, message: message, line: line}, current_block())
        Process.put(@failures, [failure | failures])
        :ok
    end
  end

  @doc """
  Runs `fun`, a template's compile or render. In a render that collects
  failures, an exception it raises is recorded as a failure of `kind` and
  `fallback` returned. Otherwise it raises, as it always has.
  """
  @spec guard(RenderFailure.kind(), term, (-> result)) :: result | term when result: term
  def guard(kind, fallback, fun) do
    if collecting?() do
      try do
        fun.()
      rescue
        error ->
          if transient?(error), do: reraise(error, __STACKTRACE__)
          record(kind, Exception.message(error), line(error))
          fallback
      end
    else
      fun.()
    end
  end

  @doc "Whether `error` is the database's, which the render should raise to be tried again."
  @spec transient?(Exception.t()) :: boolean
  def transient?(%{__struct__: struct}), do: struct in @transient

  defp line(%{line: line}) when is_integer(line) and line > 0, do: line
  defp line(_error), do: nil

  defp current_block do
    case Process.get(@blocks) do
      [current | _] -> current
      _ -> nil
    end
  end

  defp put_block(failure, nil), do: failure

  defp put_block(failure, {block, modules}) do
    module_id = Map.get(block, :module_id)
    origin = if module_id, do: Map.get(block, :module_origin) || :local
    module = module_id && find_module(modules, module_id, origin)

    %{
      failure
      | block_uid: Map.get(block, :uid),
        block_id: Map.get(block, :id),
        block_type: Map.get(block, :type),
        module_id: module_id,
        module_origin: origin,
        module_uid: module && module.uid,
        module_name: module && Brando.Content.StaleBlocks.module_name(module)
    }
  end

  defp find_module(modules, id, origin) when is_list(modules) do
    case Brando.Content.find_module(modules, id, origin) do
      {:ok, module} -> module
      _ -> nil
    end
  end

  defp find_module(_modules, _id, _origin), do: nil
end
