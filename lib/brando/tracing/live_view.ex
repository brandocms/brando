defmodule Brando.Tracing.LiveView do
  @moduledoc """
  Spans for the LiveView work Phoenix's instrumentation leaves out:

    * `<View>.render`: rendering a LiveView and computing its diff, components
      included. Runs after every callback that changed assigns.
    * `<Component>.render`: re-rendering a component after `send_update/3`.
    * `<Component>.update`: a component's `update/2` or `update_many/1`.

  Component work during a LiveView render nests under its render span. A
  render that follows `handle_event` starts its own trace, since LiveView
  renders after the event's span has ended.

  Opt in from the application's `start/2`, after `OpentelemetryPhoenix.setup/1`:

      Brando.Tracing.LiveView.setup()

  A mount of a large entry renders hundreds of components, so expect hundreds
  of spans per mount.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias OpenTelemetry.Span

  @events [
    [:phoenix, :live_view, :render, :start],
    [:phoenix, :live_view, :render, :stop],
    [:phoenix, :live_view, :render, :exception],
    [:phoenix, :live_component, :update, :start],
    [:phoenix, :live_component, :update, :stop],
    [:phoenix, :live_component, :update, :exception]
  ]

  @doc "Attaches the telemetry handlers."
  @spec setup() :: :ok | {:error, :already_exists}
  def setup do
    :telemetry.attach_many({__MODULE__, :spans}, @events, &__MODULE__.handle_event/4, nil)
  end

  @doc false
  def handle_event([_, kind, action, :start], _measurements, metadata, _config) do
    parent = Tracer.current_span_ctx()
    span = Tracer.start_span(name(kind, action, metadata), %{attributes: attributes(kind, action, metadata)})
    Tracer.set_current_span(span)
    Process.put(key(metadata), {span, parent})
  end

  def handle_event([_, _kind, _action, :stop], _measurements, metadata, _config) do
    finish(metadata)
  end

  def handle_event([_, _kind, _action, :exception], _measurements, metadata, _config) do
    with %{kind: kind, reason: reason, stacktrace: stacktrace} <- metadata,
         {span, _parent} <- Process.get(key(metadata)) do
      exception = Exception.normalize(kind, reason, stacktrace)

      if is_exception(exception),
        do: Brando.Tracing.error(span, exception, stacktrace),
        else: Span.set_status(span, OpenTelemetry.status(:error, ""))
    end

    finish(metadata)
  end

  defp finish(metadata) do
    case Process.delete(key(metadata)) do
      {span, parent} ->
        Span.end_span(span)
        Tracer.set_current_span(parent)

      nil ->
        :ok
    end
  end

  defp key(%{telemetry_span_context: ref}), do: {__MODULE__, ref}

  defp name(:live_view, :render, %{component: component}) when is_atom(component) and not is_nil(component),
    do: "#{inspect(component)}.render"

  defp name(:live_view, :render, %{socket: socket}), do: "#{inspect(socket.view)}.render"
  defp name(:live_component, :update, %{component: component}), do: "#{inspect(component)}.update"

  defp attributes(:live_view, :render, metadata) do
    %{
      "brando.lv.view": inspect(metadata.socket.view),
      "brando.lv.force": Map.get(metadata, :force?, false),
      "brando.lv.changed": Map.get(metadata, :changed?, false)
    }
  end

  defp attributes(:live_component, :update, metadata) do
    %{
      "brando.lv.view": inspect(metadata.socket.view),
      "brando.lv.component_count": length(metadata.assigns_sockets)
    }
  end
end
