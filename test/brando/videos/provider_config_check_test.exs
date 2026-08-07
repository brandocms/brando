defmodule Brando.Videos.ProviderConfigCheckTest do
  @moduledoc """
  Boot-time reporting of misconfigured video providers.

  The audit carried "nothing validates provider config at boot" as an open item
  for two phases. Pre-flight validation made a bad deploy *harmless* — the pick
  is rejected instead of killing the editor's LiveView — but it was still
  discovered by the first person to try uploading. This closes the timing half.

  These assert `problems/0` directly rather than through the log, because
  `config/test.exs` pins `config :logger, level: :error` and this suite has
  twice been bitten by capture-based assertions that could not see what they
  claimed to (recorded in the scratchpad under the gallery work and Phase 3).
  """
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Videos.ProviderConfigCheck, as: Check
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux

  setup do
    # A clean slate: no provider configured, and a default strategy that needs
    # none. Every test below opts into exactly the misconfiguration it is about.
    put_test_env(Mux, [])
    put_test_env(Bunny, [])
    put_test_env(Cloudflare, [])
    put_test_env(:default_video_upload_strategy, :local)
    :ok
  end

  # The most important case, and the reason the check is narrow: a site not
  # using a provider must not be nagged about it on every boot. A check that
  # cries wolf is a check people learn to scroll past.
  test "an unconfigured provider is not a problem" do
    assert Check.problems() == []
  end

  test "a fully configured provider is not a problem" do
    put_test_env(Mux,
      access_token_id: "id",
      access_token_secret: "secret",
      webhook_secret: "webhook"
    )

    assert Check.problems() == []
  end

  # Partial credentials cannot be intentional — nobody sets MUX_TOKEN_ID and
  # deliberately omits MUX_TOKEN_SECRET. This is the unambiguous deploy mistake.
  test "partial credentials are reported, naming what is set and what is missing" do
    put_test_env(Mux, access_token_id: "id", webhook_secret: "webhook")

    assert [problem] = Check.problems()
    assert problem =~ "mux"
    assert problem =~ "access_token_id"
    assert problem =~ "access_token_secret"
  end

  # An empty string is the shape a missing environment variable takes, and it is
  # the case the providers' own checks were tightened for.
  test "an empty-string credential counts as missing" do
    put_test_env(Cloudflare, account_id: "account", api_token: "", webhook_secret: "webhook")

    assert [problem] = Check.problems()
    assert problem =~ "cloudflare"
    assert problem =~ "api_token"
  end

  # Credentials are usable but the upload can never finish, and — worse — the
  # control silently does not render, so there is nothing for an editor to
  # report. Exactly the kind of failure that needs a boot-time voice.
  test "usable credentials without a webhook secret are reported" do
    put_test_env(Mux, access_token_id: "id", access_token_secret: "secret")

    assert [problem] = Check.problems()
    assert problem =~ "webhook_secret"
    assert problem =~ "never complete"
  end

  test "bunny accepts its read-only api key in place of a webhook secret" do
    put_test_env(Bunny, api_key: "api", read_only_api_key: "ro")

    assert Check.problems() == []
  end

  test "the default strategy must be usable" do
    put_test_env(:default_video_upload_strategy, :bunny)

    assert [problem] = Check.problems()
    assert problem =~ "default_video_upload_strategy"
    assert problem =~ "bunny"
  end

  # The default-strategy check and the per-provider checks are independent, and
  # a site can be wrong in both ways at once.
  test "a partially configured default strategy reports both problems" do
    put_test_env(:default_video_upload_strategy, :cloudflare)
    put_test_env(Cloudflare, account_id: "account")

    problems = Check.problems()

    assert length(problems) == 2
    assert Enum.any?(problems, &(&1 =~ "api_token"))
    assert Enum.any?(problems, &(&1 =~ "default_video_upload_strategy"))
  end

  describe "run/0" do
    test "returns :ok and does not raise when problems exist" do
      put_test_env(Mux, access_token_id: "id")

      assert Check.run() == :ok
    end

    test "returns :ok on a clean configuration" do
      assert Check.run() == :ok
    end

    # Opt-in only. Off by default because it decides whether an application
    # boots, which is not a behaviour anyone should inherit by upgrading.
    test "raises instead when strict mode is enabled" do
      put_test_env(:strict_video_provider_config, true)
      put_test_env(Mux, access_token_id: "id")

      assert_raise RuntimeError, ~r/access_token_secret/, fn -> Check.run() end
    end

    test "strict mode does not raise on a clean configuration" do
      put_test_env(:strict_video_provider_config, true)

      assert Check.run() == :ok
    end
  end
end
