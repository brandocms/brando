defmodule Mix.Brando.Igniter.DockerfileFrontendTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase

  # Lett's Dockerfile before the upgrade: the admin on node:22 already, the
  # frontend still on node:16, and a frontend package.json without engines.
  @dockerfile """
  FROM --platform=linux/amd64 twined/fehn:3.9 as deps
  WORKDIR /opt/app

  FROM node:22 AS assets_backend
  WORKDIR /opt/app/assets/backend
  RUN yarn build

  FROM node:16 AS assets_frontend
  WORKDIR /opt/app/assets/frontend
  COPY assets/frontend/package.json assets/frontend/yarn.lock ./
  RUN yarn build
  """

  defp package(engines) do
    Jason.encode!(Map.merge(%{"name" => "lett", "scripts" => %{"build" => "vite build"}}, engines))
  end

  defp upgrade(files) do
    IgniterCase.phoenix_project(files: Map.merge(%{"Dockerfile" => @dockerfile}, files))
    |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Backend, ["--upgrade"])
  end

  defp frontend_from(plan),
    do: plan |> IgniterCase.source("Dockerfile") |> String.split("\n") |> Enum.find(&(&1 =~ "AS assets_frontend"))

  defp frontend_notice(plan), do: Enum.find(plan.notices, &(&1 =~ "assets_frontend"))

  test "moves the frontend to the admin's Node when its package sets no engines.node" do
    plan = upgrade(%{"assets/frontend/package.json" => package(%{})})

    assert frontend_from(plan) == "FROM node:24 AS assets_frontend"
    assert frontend_notice(plan) =~ "now builds on node:24 (was node:16)"
    assert frontend_notice(plan) =~ "sets no engines.node"
    assert IgniterCase.source(plan, "Dockerfile") =~ "COPY assets/frontend/package.json assets/frontend/yarn.lock ./"
  end

  test "moves it when engines.node allows that major, keeping the image's variant" do
    dockerfile = String.replace(@dockerfile, "FROM node:16 AS", "FROM node:16.20-bookworm-slim AS")

    plan =
      upgrade(%{
        "Dockerfile" => dockerfile,
        "assets/frontend/package.json" => package(%{"engines" => %{"node" => ">=16 <25"}})
      })

    assert frontend_from(plan) == "FROM node:24-bookworm-slim AS assets_frontend"
    assert frontend_notice(plan) =~ ~s|allows it (engines.node ">=16 <25")|
  end

  test "keeps it, and says why, when engines.node excludes that major" do
    plan = upgrade(%{"assets/frontend/package.json" => package(%{"engines" => %{"node" => "^16.20.0"}})})

    assert frontend_from(plan) == "FROM node:16 AS assets_frontend"
    notice = frontend_notice(plan)
    assert notice =~ "still builds on node:16"
    assert notice =~ ~s|requires Node "^16.20.0" (engines.node), which excludes Node 24.|
  end

  test "keeps it when engines.node cannot be read" do
    plan = upgrade(%{"assets/frontend/package.json" => package(%{"engines" => %{"node" => "lts/*"}})})

    assert frontend_from(plan) == "FROM node:16 AS assets_frontend"
    assert frontend_notice(plan) =~ ~s|cannot read assets/frontend/package.json's engines.node "lts/*"|
  end

  test "keeps an image that is not node:<version>" do
    dockerfile = String.replace(@dockerfile, "FROM node:16 AS", "FROM ghcr.io/acme/node-builder:3 AS")
    plan = upgrade(%{"Dockerfile" => dockerfile, "assets/frontend/package.json" => package(%{})})

    assert frontend_from(plan) == "FROM ghcr.io/acme/node-builder:3 AS assets_frontend"
    assert frontend_notice(plan) =~ "does not build on a `node:<version>` image"
  end

  test "never moves it down, nor a pinned digest or an unusual variant" do
    package = %{"assets/frontend/package.json" => package(%{})}

    newer = String.replace(@dockerfile, "FROM node:16 AS", "FROM node:26 AS")
    plan = upgrade(Map.put(package, "Dockerfile", newer))
    assert frontend_from(plan) == "FROM node:26 AS assets_frontend"
    refute frontend_notice(plan)

    for {image, reason} <- [
          {"node:16@sha256:0123abcd", "pinned to a digest"},
          {"node:16-buster-slim", "variant may not be published"},
          {"node:16-alpine3.15", "variant may not be published"}
        ] do
      plan = upgrade(Map.put(package, "Dockerfile", String.replace(@dockerfile, "FROM node:16 AS", "FROM #{image} AS")))
      assert frontend_from(plan) == "FROM #{image} AS assets_frontend"
      assert frontend_notice(plan) =~ "still builds on #{image}"
      assert frontend_notice(plan) =~ reason
    end
  end

  test "is idempotent" do
    plan = upgrade(%{"assets/frontend/package.json" => package(%{})})
    rerun = plan |> IgniterCase.apply_and_reload() |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Backend, ["--upgrade"])

    Igniter.Test.assert_unchanged(rerun, "Dockerfile")
    refute frontend_notice(rerun)
  end
end
