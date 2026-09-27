defmodule Brando.Villain.RenderScopeTest do
  use ExUnit.Case, async: false

  alias Brando.Tenant
  alias Brando.Villain.RenderScope

  test "nested renders share inputs, but a later render reloads them" do
    load = fn ->
      send(self(), :loaded)
      make_ref()
    end

    value =
      RenderScope.run(fn ->
        first = RenderScope.fetch(:source, load)
        assert RenderScope.run(fn -> RenderScope.fetch(:source, load) end) == first
        first
      end)

    assert_received :loaded
    refute_received :loaded
    refute RenderScope.run(fn -> RenderScope.fetch(:source, load) end) == value
    assert_received :loaded
  end

  test "failed renders release inputs" do
    assert_raise RuntimeError, "render failed", fn ->
      RenderScope.run(fn ->
        RenderScope.fetch(:source, fn -> :stale end)
        raise "render failed"
      end)
    end

    assert RenderScope.run(fn -> RenderScope.fetch(:source, fn -> :fresh end) end) == :fresh
  end

  test "tenant switches inside a render cannot reuse another tenant's inputs" do
    previous = Application.get_env(:brando, :tenancy_mode)
    Application.put_env(:brando, :tenancy_mode, :multi)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, :tenancy_mode, previous),
        else: Application.delete_env(:brando, :tenancy_mode)
    end)

    RenderScope.run(fn ->
      for prefix <- ["tenant_alpha_production", "tenant_beta_production", "tenant_alpha_preview"] do
        Tenant.with_prefix(prefix, fn ->
          assert RenderScope.fetch(:source, fn -> prefix end) == prefix
        end)
      end
    end)
  end
end
