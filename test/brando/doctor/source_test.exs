defmodule Brando.Doctor.SourceTest do
  use ExUnit.Case, async: true

  alias Brando.Doctor.Source
  alias Brando.Doctor.Source.Lock

  doctest Source
  doctest Lock

  @url "https://github.com/brandocms/brando.git"
  @commit "12c2289e98fa058a8168720b802c13b42a2c21b4"
  @latest "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"

  describe "from_build/2" do
    test "Brando compiled as the project itself is this checkout" do
      root = File.cwd!()
      assert Source.current() == %{type: :checkout}

      assert Source.from_build(%{scm: Mix.SCM.Path, lockfile: Path.join(root, "mix.lock"), lock: nil}, root) == %{
               type: :checkout
             }
    end

    test "a git dependency is its locked commit and branch" do
      build = %{scm: Mix.SCM.Git, lockfile: "/app/mix.lock", lock: {:git, @url, @commit, [branch: "main"]}}

      assert %{type: :git, url: @url, commit: @commit, branch: "main", tag: nil, ref: nil} =
               Source.from_build(build, "/app/deps/brando")
    end

    test "a Hex dependency is its locked version" do
      lock = {:hex, :brando, "0.55.0", "inner", [:mix], [], "hexpm", "outer"}
      build = %{scm: Hex.SCM, lockfile: "/app/mix.lock", lock: lock}

      assert Source.from_build(build, "/app/deps/brando") == %{type: :hex, version: "0.55.0"}
    end

    test "a path dependency, as in the E2E project, is its path from the application" do
      root = File.cwd!()
      lockfile = Path.join([root, "e2e", "mix.lock"])

      # Mix does not lock path dependencies
      assert Lock.entry(File.read!(lockfile), :brando) == nil
      assert Source.from_build(%{scm: Mix.SCM.Path, lockfile: lockfile, lock: nil}, root) == %{type: :path, path: ".."}

      assert Source.from_build(%{scm: Mix.SCM.Path, lockfile: "/sites/app/mix.lock", lock: nil}, "/sites/brando") ==
               %{type: :path, path: "../brando"}
    end

    test "anything else is unknown" do
      assert Source.from_build(:unknown, "/") == %{type: :unknown}
      assert Source.from_build(%{scm: SomeSCM, lockfile: "/app/mix.lock", lock: nil}, "/brando") == %{type: :unknown}
      assert Source.from_lock({:svn, "x"}) == %{type: :unknown}
    end
  end

  describe "Lock.entry/2" do
    test "reads git and Hex entries from a lock like an application's" do
      contents = """
      %{
        "brando": {:git, "#{@url}", "#{@commit}", []},
        "jason": {:hex, :jason, "1.4.4", "b9226785a9aa77b6857ca22832cffa5d5011a667207eb2a0ad56adb5db443b8a", [:mix], [{:decimal, "~> 1.0 or ~> 2.0", [hex: :decimal, repo: "hexpm", optional: true]}], "hexpm", "c5eb0cab91f094599f94d55bc63409236a8ec69a21a67814529e8d5f6cc90b3b"},
      }
      """

      assert Lock.entry(contents, :brando) == {:git, @url, @commit, []}

      assert {:hex, :jason, "1.4.4", _, [:mix], [{:decimal, _, [hex: :decimal, repo: "hexpm", optional: true]}], "hexpm",
              _} =
               Lock.entry(contents, :jason)

      assert Source.from_lock(Lock.entry(contents, :jason)) == %{type: :hex, version: "1.4.4"}
    end

    test "reads Brando's own lock" do
      assert {:hex, :jason, _, _, _, _, "hexpm", _} = "mix.lock" |> File.read!() |> Lock.entry(:jason)
    end

    test "evaluates nothing" do
      assert Lock.entry(~s|%{"brando": {:git, System.halt(), "abc", []}}|, :brando) == nil
      assert Lock.entry(~s|%{"brando": File.rm_rf!("/")}|, :brando) == nil
      assert Lock.entry("not a lock {", :brando) == nil
      assert Lock.entry("[]", :brando) == nil
    end
  end

  test "describe/1" do
    git = Source.from_lock({:git, @url, @commit, []})

    assert Source.describe(%{git | branch: "main"}) == "git 12c2289, branch main"
    assert Source.describe(%{git | tag: "v0.55.0"}) == "git 12c2289, tag v0.55.0"
    assert Source.describe(git) == "git 12c2289"
    assert Source.describe(%{type: :hex, version: "0.55.0"}) == "Hex"
    assert Source.describe(%{type: :path, path: ".."}) == "path .."
    assert Source.describe(%{type: :checkout}) == "this checkout"
    assert Source.describe(%{type: :unknown}) == nil
    assert Source.describe(nil) == nil
  end

  describe "latest_commit/2" do
    setup do
      %{source: Source.from_lock({:git, @url, @commit, [branch: "main"]})}
    end

    test "asks the remote for the branch's commit", %{source: source} do
      test = self()

      runner = fn cmd, args, opts ->
        send(test, {:ran, cmd, args, opts[:env]})
        {"#{@latest}\trefs/heads/main\n", 0}
      end

      assert Source.latest_commit(source, runner: runner) == @latest
      assert_received {:ran, "git", ["ls-remote", "--", @url, "refs/heads/main"], env}
      assert {"GIT_TERMINAL_PROMPT", "0"} in env
    end

    test "the default branch when the lock names none", %{source: source} do
      test = self()

      runner = fn _cmd, ["ls-remote", "--", _url, ref], _opts ->
        send(test, {:ref, ref})
        {"#{@latest}\tHEAD\n", 0}
      end

      assert Source.latest_commit(%{source | branch: nil}, runner: runner) == @latest
      assert_received {:ref, "HEAD"}
    end

    test "nil on any failure", %{source: source} do
      assert Source.latest_commit(source, runner: fn _, _, _ -> {"fatal: could not read Username", 128} end) == nil
      assert Source.latest_commit(source, runner: fn _, _, _ -> {"", 0} end) == nil
      assert Source.latest_commit(source, runner: fn _, _, _ -> raise ErlangError, original: :enoent end) == nil

      slow = fn _, _, _ ->
        Process.sleep(1_000)
        {"#{@latest}\trefs/heads/main\n", 0}
      end

      assert Source.latest_commit(source, runner: slow, timeout: 20) == nil
    end

    test "a tag, a pinned ref and other sources are not looked up", %{source: source} do
      runner = fn _, _, _ -> flunk("ran git") end

      assert Source.latest_commit(%{source | tag: "v0.55.0"}, runner: runner) == nil
      assert Source.latest_commit(%{source | ref: @commit}, runner: runner) == nil
      assert Source.latest_commit(%{type: :checkout}, runner: runner) == nil
      assert Source.latest_commit(nil, runner: runner) == nil
    end

    test "runs git ls-remote against a repository" do
      if System.find_executable("git") do
        {head, 0} = System.cmd("git", ["rev-parse", "HEAD"])
        source = %{type: :git, url: File.cwd!(), commit: @commit, branch: nil, tag: nil, ref: nil}

        assert Source.latest_commit(source) == String.trim(head)
      end
    end
  end
end
