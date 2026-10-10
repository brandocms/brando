defmodule Brando.Tracing do
  @moduledoc """
  OpenTelemetry spans around Brando's own work: rendering blocks, mutations,
  revisions, saving and loading admin forms, live preview, image processing
  and caches. Span names start with `brando.`; attributes with `brando.`.

  Brando depends on `opentelemetry_api`, not the SDK. Without the `opentelemetry` SDK,
  or with `traces_exporter: :none`, a span costs a function call, so the spans
  stay in place in every application. To record them, add the SDK and an
  exporter to the application (`mix brando.gen.otel` does both, along with the
  Phoenix, LiveView, Ecto and Oban instrumentation).

  Phoenix's instrumentation traces LiveView mounts, `handle_params` and
  `handle_event`, but not LiveComponent `update/2` or rendering, where much of
  the admin's work happens. `Brando.Tracing.LiveView.setup/0` adds those.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias OpenTelemetry.Span

  @type attributes :: %{optional(atom() | String.t()) => term()}

  @doc """
  Runs `fun` inside a span named `name` and returns its result.

  Attributes whose value is `nil` are left out, and a module is recorded by
  name. To trace a whole function, `Brando.Tracing.Decorator` is shorter.

  An exception or exit is recorded on the span (its type and stack trace, not
  its message) and re-raised. A throw passes through unrecorded,
  since Ecto's `rollback/1` and other control flow use it.
  """
  @spec span(String.t(), attributes(), (-> result)) :: result when result: var
  def span(name, attributes \\ %{}, fun) when is_function(fun, 0) do
    Tracer.with_span name, %{attributes: compact(attributes)} do
      try do
        fun.()
      catch
        :error, reason ->
          error(Exception.normalize(:error, reason, __STACKTRACE__), __STACKTRACE__)
          :erlang.raise(:error, reason, __STACKTRACE__)

        :exit, reason ->
          Tracer.set_status(OpenTelemetry.status(:error, exit_message(reason)))
          :erlang.raise(:exit, reason, __STACKTRACE__)
      end
    end
  end

  @doc "Adds attributes known only partway through to the current span."
  @spec set_attributes(attributes()) :: :ok
  def set_attributes(attributes) do
    Tracer.set_attributes(compact(attributes))
    :ok
  end

  @doc """
  Captures the current trace context, so spans started in another process
  join the caller's trace. Pass the result to `with_context/2` there.
  """
  @spec capture() :: OpenTelemetry.Ctx.t()
  def capture, do: OpenTelemetry.Ctx.get_current()

  @doc """
  Runs `fun` with a context from `capture/0` attached, then restores the
  previous one, so a callback run in the capturing process itself (an
  after-commit hook) does not leave a finished span current.
  """
  @spec with_context(OpenTelemetry.Ctx.t(), (-> result)) :: result when result: var
  def with_context(ctx, fun) do
    token = OpenTelemetry.Ctx.attach(ctx)

    try do
      fun.()
    after
      OpenTelemetry.Ctx.detach(token)
    end
  end

  @doc false
  # Only the exception's type and where it was raised are exported. Its
  # message and a stack trace's arguments can hold the data being processed
  # (a `MatchError` carries the value, a `FunctionClauseError` the arguments).
  def error(span \\ Tracer.current_span_ctx(), exception, stacktrace) do
    type = inspect(exception.__struct__)
    stacktrace = Enum.map(stacktrace, &without_arguments/1)

    Span.add_event(span, "exception", %{
      "exception.type": type,
      "exception.stacktrace": Exception.format_stacktrace(stacktrace)
    })

    Span.set_status(span, OpenTelemetry.status(:error, type))
  end

  defp without_arguments({module, fun, args, location}) when is_list(args), do: {module, fun, length(args), location}
  defp without_arguments(entry), do: entry

  # A `GenServer.call/3` exit carries the call's message; export only its reason.
  defp exit_message(reason) when is_atom(reason), do: "exit: #{reason}"
  defp exit_message({reason, {_module, _function, _args}}) when is_atom(reason), do: "exit: #{reason}"
  defp exit_message(_reason), do: "exit"

  defp compact(attributes) when attributes == %{}, do: attributes

  defp compact(attributes) do
    for {key, value} <- attributes, not is_nil(value), into: %{}, do: {key, attribute(value)}
  end

  # A module is recorded by name: "Brando.Pages.Page", not "Elixir.Brando.Pages.Page".
  defp attribute(value) when is_atom(value) and value not in [true, false] do
    case Atom.to_string(value) do
      "Elixir." <> name -> name
      _ -> value
    end
  end

  defp attribute(value), do: value
end
