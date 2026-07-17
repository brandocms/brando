defmodule Brando.Assets.CompletedCallbackTest do
  use ExUnit.Case, async: true

  alias Brando.Assets.CompletedCallback

  def mfa_callback(asset, user, pid, marker) do
    send(pid, {:completed, asset, user, marker})
  end

  test "validates and invokes function callbacks" do
    callback = fn asset, user -> send(self(), {:completed, asset, user}) end

    assert :ok = CompletedCallback.validate(callback)
    assert :ok = CompletedCallback.run(%{completed_callback: callback}, :asset, :system)
    assert_received {:completed, :asset, :system}
  end

  test "invokes MFA callbacks with runtime arguments first" do
    callback = {__MODULE__, :mfa_callback, [self(), :configured]}

    assert :ok = CompletedCallback.validate(callback)
    assert :ok = CompletedCallback.run(%{completed_callback: callback}, :asset, :system)
    assert_received {:completed, :asset, :system, :configured}
  end

  test "rejects invalid callback shapes and skips absent callbacks" do
    assert :ok = CompletedCallback.run(%{}, :asset, :system)
    assert {:error, message} = CompletedCallback.validate({__MODULE__, :mfa_callback, :not_a_list})
    assert message =~ "arity-2 function"

    assert_raise ArgumentError, ~r/arity-2 function/, fn ->
      CompletedCallback.run(%{completed_callback: :invalid}, :asset, :system)
    end
  end
end
