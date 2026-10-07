defmodule Brando.Users.ThrottleTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Users.SecurityEvent
  alias Brando.Users.Throttle
  alias Brando.Users.UserConfig

  defp ip, do: "10.#{:rand.uniform(250)}.#{:rand.uniform(250)}.#{System.unique_integer([:positive]) |> rem(250)}"
  defp email, do: "throttle-#{System.unique_integer([:positive])}@example.test"

  test "limits sign-in attempts per IP address and per account" do
    ip = ip()
    limit = Throttle.config()[:login_per_ip]

    for _ <- 1..limit, do: assert(:ok = Throttle.check_login(ip, email()))
    assert {:error, :rate_limited, retry_after} = Throttle.check_login(ip, email())
    assert retry_after > 0

    address = email()
    for _ <- 1..Throttle.config()[:login_per_account], do: assert(:ok = Throttle.check_login(ip(), address))
    assert {:error, :rate_limited, _} = Throttle.check_login(ip(), String.upcase(address))
  end

  test "limits two-factor codes per IP address" do
    ip = ip()
    for _ <- 1..Throttle.config()[:two_factor_per_ip], do: assert(:ok = Throttle.check_two_factor(ip))
    assert {:error, :rate_limited, _} = Throttle.check_two_factor(ip)
  end

  test "limits password reset requests per IP address, and quietly per account" do
    address = email()
    for _ <- 1..Throttle.config()[:reset_per_account], do: assert(:ok = Throttle.check_reset(ip(), address))
    assert {:error, :account_limited, _} = Throttle.check_reset(ip(), address)

    ip = ip()
    for _ <- 1..Throttle.config()[:reset_per_ip], do: assert(:ok = Throttle.check_reset(ip, email()))
    assert {:error, :ip_limited, _} = Throttle.check_reset(ip, email())
  end

  test "locks an account after repeated failures, and a sign-in starts the count again" do
    user = Factory.insert(:random_user, config: %UserConfig{})
    after_count = Throttle.config()[:lockout_after]

    for _ <- 1..(after_count - 2), do: assert(:ok = Throttle.failed(user, :password))
    Throttle.clear(user)
    for _ <- 1..(after_count - 1), do: assert(:ok = Throttle.failed(user, :password))
    refute Throttle.locked_until(user)

    assert {:locked, until} = Throttle.failed(user, :two_factor, %{ip: "10.0.0.1"})
    assert DateTime.compare(until, DateTime.utc_now()) == :gt
    assert Throttle.locked_until(user)

    actions =
      Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id, select: e.action)

    assert Enum.count(actions, &(&1 == :login_failed)) == 2 * after_count - 2
    assert :locked in actions

    Throttle.clear(user)
    refute Throttle.locked_until(user)
  end

  test "an address with no account is answered as a locked one would be" do
    address = email()
    for _ <- 1..(Throttle.config()[:lockout_after] - 1), do: assert(:ok = Throttle.failed_unknown(address))
    refute Throttle.unknown_locked?(address)
    assert {:locked, _} = Throttle.failed_unknown(address)
    assert Throttle.unknown_locked?(address)
  end
end
