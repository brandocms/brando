Code.require_file("../../credo/checks/test_cache_restore.ex", __DIR__)

defmodule Brando.Credo.Check.TestCacheRestoreTest do
  use Credo.Test.Case

  alias Brando.Credo.Check.TestCacheRestore

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(source) do
    source
    |> to_source_file("test/sample_test.exs")
    |> run_check(TestCacheRestore)
  end

  test "flags a cache write in a module with no restore" do
    """
    defmodule SampleTest do
      setup do
        Brando.Cache.SEO.set()
        :ok
      end

      test "x" do
        Cachex.clear(:query)
        Brando.Cache.put(:identity, :stale, :infinite)
      end
    end
    """
    |> issues()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["Brando.Cache.SEO.set", "Cachex.clear", "Brando.Cache.put"]
    end)
  end

  test "follows aliases" do
    """
    defmodule SampleTest do
      alias Brando.Cache
      alias Brando.Cache.{Globals, Identity}

      test "x" do
        Cache.update(:seo, %{})
        Globals.set()
        Identity.update({:ok, %{}})
      end
    end
    """
    |> issues()
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "accepts an on_exit that writes a cache back" do
    """
    defmodule SampleTest do
      setup do
        cached = Brando.Cache.get(:identity)
        on_exit(fn -> Brando.Cache.put(:identity, cached, :infinite) end)
      end

      test "x", do: Brando.Cache.Identity.set()
    end
    """
    |> issues()
    |> refute_issues()
  end

  test "accepts an on_exit that restores through the module's own function" do
    """
    defmodule SampleTest do
      setup do
        previous = Cachex.get(:cache, :identity)
        on_exit(fn -> restore(previous) end)
      end

      test "x", do: Brando.Cache.put(:identity, %{}, :infinite)

      defp restore({:ok, nil}), do: Cachex.del(:cache, :identity)
      defp restore({:ok, value}), do: Cachex.put(:cache, :identity, value)
    end
    """
    |> issues()
    |> refute_issues()
  end

  test "accepts preserve_cache/1" do
    """
    defmodule SampleTest do
      setup do
        preserve_cache(:seo)
      end

      test "x", do: Brando.Cache.SEO.set()
    end
    """
    |> issues()
    |> refute_issues()
  end

  test "leaves reads and single-key removals alone" do
    """
    defmodule SampleTest do
      test "x" do
        Brando.Cache.get(:identity)
        Brando.Cache.del({:starting_modules, "en"})
        Brando.Cache.Query.evict(%{id: 1})
        Cachex.put(:cache, {:throttle, "a@b.c"}, 1)
      end
    end
    """
    |> issues()
    |> refute_issues()
  end
end
