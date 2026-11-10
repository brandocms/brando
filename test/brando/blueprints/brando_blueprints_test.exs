defmodule Brando.Blueprint.BrandoBlueprintsTest do
  # Sets `:otp_app`, which is global application env.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Authorization.Catalog

  # What finding Blueprints did before `brando_blueprints/0`: load every
  # module of each application and keep the Blueprints.
  defp full_scan(apps) do
    apps
    |> Enum.uniq()
    |> Enum.flat_map(fn app ->
      case :application.get_key(app, :modules) do
        {:ok, modules} -> modules
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Brando.Blueprint.load_modules()
    |> Enum.filter(&Brando.Blueprint.blueprint?/1)
  end

  # The test build compiles test/support into `:brando` too; a release has
  # only lib/.
  defp in_lib?(module) do
    module.module_info(:compile)[:source] |> to_string() |> String.starts_with?(Path.expand("lib") <> "/")
  end

  test "brando_blueprints/0 lists every Blueprint in lib/, in the application's module order" do
    in_lib = :brando |> List.wrap() |> full_scan() |> Enum.filter(&in_lib?/1)

    assert Brando.Blueprint.brando_blueprints() == in_lib,
           """
           Brando.Blueprint's @brando_blueprints is out of date.
           Missing: #{inspect(in_lib -- Brando.Blueprint.brando_blueprints())}
           Not Blueprints in lib/: #{inspect(Brando.Blueprint.brando_blueprints() -- in_lib)}
           """
  end

  test "app_blueprints/1 is the application's Blueprints, and none for an application not loaded" do
    assert Brando.Blueprint.app_blueprints(:brando) == full_scan([:brando])
    assert Brando.Blueprint.app_blueprints(:ecto) == []
    assert Brando.Blueprint.app_blueprints(:no_such_application) == []
    assert Brando.Blueprint.app_blueprints(nil) == []
  end

  describe "Catalog.schemas/0" do
    test "is the full scan of Brando and the site, Brando's first" do
      # A site's application: Brando's Blueprints come from the list, the
      # site's from its own modules.
      put_test_env(:otp_app, :ecto)
      assert Catalog.schemas() == [:brando, :ecto] |> full_scan() |> Enum.filter(&in_lib?/1)
    end

    test "holds the same schemas as the full scan when Brando is the application" do
      put_test_env(:otp_app, :brando)
      assert MapSet.new(Catalog.schemas()) == MapSet.new(full_scan([:brando]))
      assert length(Catalog.schemas()) == length(full_scan([:brando]))
    end
  end
end
