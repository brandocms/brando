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
    refute Throttle.unknown_locked_until(address)
    assert {:locked, until} = Throttle.failed_unknown(address)
    assert Throttle.unknown_locked_until(address) == until
  end

  describe "repeated lockouts" do
    defp lock(fun) do
      Enum.reduce(1..Throttle.config()[:lockout_after], nil, fn _, _ -> fun.() end)
    end

    defp minutes_until(until), do: round(DateTime.diff(until, DateTime.utc_now()) / 60)

    test "last longer each time within a day, and the user is emailed" do
      user = Factory.insert(:random_user, config: %UserConfig{})

      unlock = fn ->
        Repo.update_all(from(s in Brando.Users.Security, where: s.user_id == ^user.id), set: [locked_until: nil])
      end

      durations =
        for _ <- 1..4 do
          {:locked, until} = lock(fn -> Throttle.failed(user, :password) end)
          unlock.()
          minutes_until(until)
        end

      assert durations == [15, 60, 240, 240]

      email = user.email
      assert_received {:email, %{to: [{"", ^email}], subject: "Your account was locked for a while"}}
    end

    test "for an unknown address too, so the answers stay alike" do
      address = email()

      durations =
        for _ <- 1..3 do
          {:locked, until} = lock(fn -> Throttle.failed_unknown(address) end)
          Cachex.del(:cache, {Throttle, :unknown_locked, address})
          minutes_until(until)
        end

      assert durations == [15, 60, 240]
    end
  end

  describe "spaced failures" do
    # Failures count in a window from the first of them, for an account and
    # for an address without one alike, so spaced guesses cannot tell them apart.
    test "an account's count starts again once its window has passed" do
      user = Factory.insert(:random_user, config: %UserConfig{})
      lockout_after = Throttle.config()[:lockout_after]
      for _ <- 1..(lockout_after - 1), do: assert(:ok = Throttle.failed(user, :password))

      window_ago = DateTime.add(DateTime.utc_now(), -(Throttle.config()[:lockout_minutes] * 60 + 1), :second)

      Repo.update_all(from(s in Brando.Users.Security, where: s.user_id == ^user.id),
        set: [failures_since: DateTime.truncate(window_ago, :second)]
      )

      assert :ok = Throttle.failed(user, :password)
      refute Throttle.locked_until(user)
    end

    test "so does an unknown address's" do
      address = email()
      lockout_after = Throttle.config()[:lockout_after]
      for _ <- 1..(lockout_after - 1), do: assert(:ok = Throttle.failed_unknown(address))

      # Its window passes
      Cachex.expire(:cache, {Throttle, :unknown_failures, address}, 1)
      Process.sleep(10)

      assert :ok = Throttle.failed_unknown(address)
      refute Throttle.unknown_locked_until(address)
    end
  end
end
