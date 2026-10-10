defmodule Brando.TracingTest do
  # The SDK records spans in the test env (config/test.exs); this module has
  # them sent to the test process.
  use ExUnit.Case, async: false

  require Record

  alias Brando.Tenant
  alias Brando.Tracing
  alias OpenTelemetry.Ctx

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  defmodule Decorated do
    @moduledoc false
    use Brando.Tracing.Decorator

    @decorate span("brando.test.plain")
    def plain(value), do: {:ok, value}

    @decorate span("brando.test.attributes",
                schema: :schema,
                entry_id: [:entry, :id],
                mode: :mode,
                missing: [:entry, :nope]
              )
    def attributes(schema, %{title: _} = entry, mode \\ :update), do: {schema, entry.id, mode}

    @decorate span("brando.test.outer")
    def outer, do: plain(1)

    @decorate span("brando.test.raises")
    def raises, do: raise(ArgumentError, "boom")

    @decorate span("brando.test.handles")
    def handles do
      raise ArgumentError, "handled"
    rescue
      ArgumentError -> :handled
    end

    @mode :first
    @decorate span("brando.test.mode")
    def mode, do: @mode
    @mode :second
    def later_mode, do: @mode

    @decorate span("brando.test.either", n: :n)
    def either(n) when is_integer(n) when is_float(n), do: {:number, n}
    def either(n), do: {:other, n}

    @decorate span("brando.test.bits")
    def bits(<<size::8, payload::binary-size(size), _rest::binary>>), do: payload

    @decorate span("brando.test.pair")
    def pair(x, _brando_unused_x), do: x

    @key :old
    @decorate span("brando.test.key")
    def key(@key), do: :old_key
    def key(_other), do: :other
    @key :new
    def new_key, do: @key

    def generation(x), do: {:first, x}
    defoverridable generation: 1
    @decorate span("brando.test.superseded")
    def generation(x), do: {:second, x}
    defoverridable generation: 1
    def generation(x), do: {:third, x}

    @decorate span("brando.test.positive")
    def sign(n) when n > 0, do: :positive
    def sign(_n), do: :other
  end

  defmodule Server do
    @moduledoc false
    use Brando.Tracing.Decorator
    use GenServer

    def init(state), do: {:ok, state}

    @decorate span("brando.test.tick")
    def handle_info(:tick, _state), do: {:noreply, :ticked}
  end

  setup do
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :otel_simple_processor.set_exporter(:none) end)
  end

  defp recorded(name) do
    assert_receive {:span, span(name: ^name) = recorded}
    recorded
  end

  defp attributes(recorded), do: recorded |> span(:attributes) |> :otel_attributes.map()

  describe "@decorate span" do
    test "returns the function's result and records a span with its arguments" do
      assert Decorated.attributes(Brando.Pages.Page, %{id: 4, title: "A"}) == {Brando.Pages.Page, 4, :update}

      assert attributes(recorded("brando.test.attributes")) == %{
               "brando.schema": "Brando.Pages.Page",
               "brando.entry_id": 4,
               "brando.mode": :update
             }
    end

    test "nests a decorated call inside another" do
      assert Decorated.outer() == {:ok, 1}

      inner = recorded("brando.test.plain")
      outer = recorded("brando.test.outer")
      assert span(inner, :parent_span_id) == span(outer, :span_id)
    end

    test "records an exception as an error and raises it" do
      assert_raise ArgumentError, "boom", &Decorated.raises/0
      raised = recorded("brando.test.raises")
      assert {:status, :error, "ArgumentError"} = span(raised, :status)
      # The message can hold the data being processed, so it is not exported.
      refute inspect(raised) =~ "boom"
    end

    test "keeps an exception the function rescues out of the span's status" do
      assert Decorated.handles() == :handled
      refute match?({:status, :error, _}, span(recorded("brando.test.handles"), :status))
    end

    test "leaves module attributes as they were where the function is defined" do
      assert {Decorated.mode(), Decorated.later_mode()} == {:first, :second}
    end

    test "matches heads exactly as the function does" do
      assert {Decorated.either(1), Decorated.either(1.5), Decorated.either(:a)} ==
               {{:number, 1}, {:number, 1.5}, {:other, :a}}

      assert Decorated.bits(<<2, "ab", "cd">>) == "ab"
      assert Decorated.pair(1, 2) == 1
      recorded("brando.test.pair")
    end

    test "matches a module attribute in a head with its value where the clause is written" do
      assert {Decorated.key(:old), Decorated.key(:new), Decorated.new_key()} == {:old_key, :other, :new}
      recorded("brando.test.key")
    end

    test "tells clauses on one line apart" do
      # From a string, so the formatter leaves both clauses on one line.
      [{module, _bytecode}] =
        Code.compile_string("""
        defmodule Brando.TracingTest.SameLine do
          use Brando.Tracing.Decorator
          @decorate span("brando.test.same_line", value: :x)
          def f(:a, x), do: x; def f(:b, y), do: {:b, y}
        end
        """)

      assert module.f(:b, 2) == {:b, 2}
      refute_received {:span, span(name: "brando.test.same_line")}
      assert module.f(:a, 1) == 1
      recorded("brando.test.same_line")
    end

    test "leaves a decorated clause a later definition replaced untraced" do
      assert Decorated.generation(1) == {:third, 1}
      refute_received {:span, span(name: "brando.test.superseded")}
    end

    test "traces a clause that replaces a default from `use GenServer`" do
      {:ok, pid} = GenServer.start_link(Brando.TracingTest.Server, nil)
      send(pid, :tick)
      assert :sys.get_state(pid) == :ticked
      recorded("brando.test.tick")
    end

    test "traces only the clauses that are decorated" do
      assert Decorated.sign(-1) == :other
      refute_received {:span, span(name: "brando.test.positive")}

      assert Decorated.sign(1) == :positive
      recorded("brando.test.positive")
    end

    test "refuses an attribute that names no argument" do
      code = """
      defmodule Brando.TracingTest.Misnamed do
        use Brando.Tracing.Decorator
        @decorate span("brando.test.misnamed", entry_id: :id)
        def misnamed(entry), do: entry
      end
      """

      assert_raise ArgumentError, ~r/has no argument named id/, fn -> Code.compile_string(code) end
    end
  end

  describe "span/3" do
    test "returns the function's result" do
      assert Tracing.span("brando.test", %{"brando.entry_id": nil}, fn -> {:ok, 1} end) == {:ok, 1}
    end

    test "re-raises errors and exits, and lets throws through" do
      assert_raise ArgumentError, fn -> Tracing.span("brando.test", fn -> raise ArgumentError end) end
      assert catch_exit(Tracing.span("brando.test", fn -> exit(:boom) end)) == :boom
      assert catch_throw(Tracing.span("brando.test", fn -> throw(:rollback) end)) == :rollback
    end
  end

  describe "with_context/2" do
    test "attaches the captured context and restores the previous one" do
      Ctx.set_value(:brando_tracing_test, :captured)
      captured = Tracing.capture()
      Ctx.set_value(:brando_tracing_test, :outer)

      assert Tracing.with_context(captured, fn -> Ctx.get_value(:brando_tracing_test, nil) end) == :captured
      assert Ctx.get_value(:brando_tracing_test, nil) == :outer

      assert_raise RuntimeError, fn -> Tracing.with_context(captured, fn -> raise "boom" end) end
      assert Ctx.get_value(:brando_tracing_test, nil) == :outer
    end
  end

  test "Tenant.capture_context/1 carries the trace context into another process" do
    Ctx.set_value(:brando_tracing_test, :caller)
    fun = Tenant.capture_context(fn -> Ctx.get_value(:brando_tracing_test, nil) end)

    assert fun |> Task.async() |> Task.await() == :caller
  end

  describe "LiveView handler" do
    test "nests a component render inside the update that caused it" do
      update = %{
        telemetry_span_context: make_ref(),
        socket: %{view: BrandoAdmin.TestView},
        component: BrandoAdmin.TestComponent,
        assigns_sockets: [{%{}, nil}]
      }

      render = %{
        telemetry_span_context: make_ref(),
        socket: %{view: BrandoAdmin.TestView},
        component: BrandoAdmin.TestComponent,
        changed?: true
      }

      Tracing.LiveView.handle_event([:phoenix, :live_component, :update, :start], %{}, update, nil)
      Tracing.LiveView.handle_event([:phoenix, :live_view, :render, :start], %{}, render, nil)
      Tracing.LiveView.handle_event([:phoenix, :live_view, :render, :stop], %{}, render, nil)
      Tracing.LiveView.handle_event([:phoenix, :live_component, :update, :stop], %{}, update, nil)

      rendered = recorded("BrandoAdmin.TestComponent.render")
      updated = recorded("BrandoAdmin.TestComponent.update")
      assert span(rendered, :parent_span_id) == span(updated, :span_id)
      assert OpenTelemetry.Tracer.current_span_ctx() == :undefined
    end

    test "clears its process state on stop and on exception" do
      for ending <- [:stop, :exception] do
        ref = make_ref()

        metadata = %{
          telemetry_span_context: ref,
          socket: %{view: BrandoAdmin.TestView},
          component: BrandoAdmin.TestComponent,
          assigns_sockets: [{%{}, nil}],
          kind: :error,
          reason: %RuntimeError{message: "boom"},
          stacktrace: []
        }

        Tracing.LiveView.handle_event([:phoenix, :live_component, :update, :start], %{}, metadata, nil)
        assert Process.get({Tracing.LiveView, ref})

        Tracing.LiveView.handle_event([:phoenix, :live_component, :update, ending], %{}, metadata, nil)
        refute Process.get({Tracing.LiveView, ref})
      end
    end
  end
end
