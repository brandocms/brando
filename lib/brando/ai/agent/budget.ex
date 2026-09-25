defmodule Brando.AI.Agent.Budget do
  @moduledoc """
  Token budgets for agent runs.

  Before each model call the run reserves an estimate — the context's size
  plus the output limit — against the run budget and the site/environment's
  monthly budget. After the call the reservation is replaced by the usage the
  provider reports. Reservations are taken under an advisory lock, so two
  concurrent runs cannot both spend the last of a budget.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.AI.Agent
  alias Brando.AI.Agent.Run
  alias Brando.Repo

  @doc "Reserve `estimate` tokens for `run`, or `{:error, :exhausted}`."
  @spec reserve(Run.t(), non_neg_integer()) :: {:ok, Run.t()} | {:error, :exhausted}
  def reserve(%Run{} = run, estimate) do
    {:ok, result} =
      Repo.transaction(fn ->
        Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "brando-ai-agent-budget:" <> run.scope
        ])

        run = Repo.get!(Run, run.id)
        config = Agent.config()
        run_total = run.input_tokens + run.output_tokens + estimate
        monthly = config[:monthly_token_budget]

        cond do
          run_total > config[:run_token_budget] -> {:error, :exhausted}
          monthly && used_this_month(run.scope, run.id) + run_total > monthly -> {:error, :exhausted}
          true -> {:ok, run |> Ecto.Changeset.change(reserved_tokens: estimate) |> Repo.update!()}
        end
      end)

    result
  end

  @doc "Replace the reservation with the reported `usage` and its estimated cost."
  @spec reconcile(Run.t(), map() | nil, String.t()) :: Run.t()
  def reconcile(%Run{} = run, usage, model) do
    usage = usage || %{}
    input = count(usage, :input_tokens)
    output = count(usage, :output_tokens)

    run = Repo.get!(Run, run.id)

    run
    |> Ecto.Changeset.change(
      reserved_tokens: 0,
      steps: run.steps + 1,
      model: model,
      input_tokens: run.input_tokens + input,
      output_tokens: run.output_tokens + output,
      cached_tokens: run.cached_tokens + count(usage, :cached_tokens),
      reasoning_tokens: run.reasoning_tokens + count(usage, :reasoning_tokens),
      cost: run.cost + cost(usage, input, output, model)
    )
    |> Repo.update!()
  end

  @doc "Tokens used and reserved this calendar month in `scope`, excluding `except_run`."
  @spec used_this_month(String.t(), Ecto.UUID.t() | nil) :: non_neg_integer()
  def used_this_month(scope, except_run \\ nil) do
    %{year: year, month: month} = DateTime.utc_now()
    {:ok, start} = DateTime.new(Date.new!(year, month, 1), ~T[00:00:00], "Etc/UTC")

    query =
      from(r in Run,
        where: r.scope == ^scope and r.inserted_at >= ^start,
        select: coalesce(sum(r.input_tokens + r.output_tokens + r.reserved_tokens), 0)
      )

    query = if except_run, do: from(r in query, where: r.id != ^except_run), else: query
    Repo.one(query) |> to_integer()
  end

  @doc "A rough token estimate for a request: about four characters per token."
  @spec estimate(term()) :: non_neg_integer()
  def estimate(payload), do: div(byte_size(:erlang.term_to_binary(payload)), 4)

  # Configured prices (USD per million tokens) win; then the cost ReqLLM
  # reports; then the model catalogue's prices. A model with no known price
  # costs zero, and its tokens still count to the budget.
  defp cost(usage, input, output, model) do
    reported = usage[:total_cost]

    case {configured_prices(), reported} do
      {{_, _} = prices, _} -> price(input, output, prices)
      {nil, reported} when is_number(reported) -> reported / 1
      {nil, _} -> price(input, output, catalogue_prices(model))
    end
  end

  defp configured_prices do
    case Agent.config()[:prices] do
      [input: i, output: o] -> {i, o}
      %{input: i, output: o} -> {i, o}
      _ -> nil
    end
  end

  defp catalogue_prices(model) do
    case Brando.AI.model_info(model: model) do
      {:ok, %{input_price: i, output_price: o}} -> {i, o}
      _ -> nil
    end
  end

  defp price(input, output, {i, o}) when is_number(i) and is_number(o), do: (input * i + output * o) / 1_000_000
  defp price(_, _, _), do: 0.0

  defp count(usage, key), do: to_integer(usage[key] || 0)

  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_float(value), do: round(value)
  defp to_integer(_), do: 0
end
