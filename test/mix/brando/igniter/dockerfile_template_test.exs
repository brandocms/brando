defmodule Mix.Brando.Igniter.DockerfileTemplateTest do
  use ExUnit.Case, async: true

  defp template, do: Application.app_dir(:brando, "priv/templates/brando.install/Dockerfile")

  # Each RUN instruction, continuation lines joined
  defp runs do
    template()
    |> File.read!()
    |> String.replace(~r/\\\n/, " ")
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "RUN "))
  end

  test "the step that holds the Sentry token fetches nothing from npm" do
    [upload] = Enum.filter(runs(), &(&1 =~ "sentry_auth_token"))

    assert upload =~ "sentry-cli sourcemaps upload"
    refute upload =~ ~r/\b(npx|npm|pnpm dlx|pnpx)\b/
  end

  test "sentry-cli is installed at an exact version, without a secret mounted" do
    [install] = Enum.filter(runs(), &(&1 =~ "@sentry/cli"))

    refute install =~ "--mount=type=secret"
    assert install =~ "@sentry/cli@${SENTRY_CLI_VERSION}"
    assert File.read!(template()) =~ ~r/^ARG SENTRY_CLI_VERSION=\d+\.\d+\.\d+$/m
  end
end
