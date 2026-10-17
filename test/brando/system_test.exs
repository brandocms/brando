defmodule Brando.SystemTest do
  use ExUnit.Case
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.Sites.Identity
  alias Brando.Sites.SEO

  test "system" do
    assert Brando.System.initialize() == :ok
  end

  describe "check_content/1" do
    setup do
      Brando.repo().delete_all(Identity)
      Brando.repo().delete_all(SEO)
      :ok
    end

    # config/test.exs logs errors only; the test is synchronous.
    defp check_content_log(env) do
      level = Logger.level()
      Logger.configure(level: :debug)

      try do
        capture_log([level: :debug], fn -> assert Brando.System.check_content(env) == :ok end)
      after
        Logger.configure(level: level)
      end
    end

    test "warns, rather than errs, when there is no identity or SEO" do
      log = check_content_log(:dev)

      assert log =~ "[warning] ==> No identities found. mix brando.gen.seeds creates them."
      assert log =~ "[warning] ==> No seo entries found. mix brando.gen.seeds creates them."
      refute log =~ "[error]"
    end

    test "says nothing in the test environment, whose database starts empty" do
      assert check_content_log(:test) == ""
    end

    test "does not warn when the content exists" do
      Brando.repo().insert!(%Identity{name: "Brando", alternate_name: "B", language: :en, type: "organization"})
      Brando.repo().insert!(%SEO{language: :en, base_url: "https://example.com"})

      log = check_content_log(:dev)

      refute log =~ "No identities found"
      refute log =~ "No seo entries found"
      assert log =~ "==> identity: [en] exists"
    end
  end
end
