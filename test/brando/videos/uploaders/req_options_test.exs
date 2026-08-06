defmodule Brando.Videos.Uploaders.ReqOptionsTest do
  @moduledoc """
  The merge rule on its own, with no provider and no transport.

  `provider_client_test.exs` pins the rule end-to-end at one of its three call
  sites, which is the test that would catch a re-inlined merge. This one is
  cheaper and covers what that cannot: the keys the rule does *not* defend.
  `ReqOptions`' `@doc` names them, and prose nobody can falsify is how the
  previous version of that doc came to claim more than the code did.
  """
  use ExUnit.Case, async: false

  alias Brando.Videos.Uploaders.ReqOptions

  # Not a real provider: `merge/2` only uses the module as an
  # `Application.get_env/3` key, so a bare atom is the whole fixture.
  @provider __MODULE__

  defp put_req_options(value) do
    original = Application.fetch_env(:brando, @provider)
    Application.put_env(:brando, @provider, req_options: value)

    on_exit(fn ->
      case original do
        {:ok, prior} -> Application.put_env(:brando, @provider, prior)
        :error -> Application.delete_env(:brando, @provider)
      end
    end)
  end

  describe "merge/2 defends the keys the built options name" do
    # MUTATION: flip the merge to `Keyword.merge(built_opts, configured || [])`.
    # This is the only test in this file that mutation reddens, which is why
    # each of the others names its own below — one blanket claim covering five
    # tests is a claim about one test and four assumptions.
    test "a built value wins over a configured one on the same key" do
      put_req_options(headers: [{"authorization", "hijacked"}], method: :delete)

      merged = ReqOptions.merge(@provider, method: :post, headers: [{"authorization", "built"}])

      assert Keyword.fetch!(merged, :headers) == [{"authorization", "built"}]
      assert Keyword.fetch!(merged, :method) == :post
    end

    # MUTATION: wrap the configured side in an allowlist —
    # `Keyword.take(configured || [], [:headers, :method, :url, :json])`.
    # Flipping the merge order does **not** redden this one: neither key is in
    # the built options, so the result is identical either way round.
    test "a configured key the built options do not name passes through" do
      put_req_options(plug: {Req.Test, :stub}, receive_timeout: 1_000)

      merged = ReqOptions.merge(@provider, method: :get, url: "https://example.com")

      assert Keyword.fetch!(merged, :plug) == {Req.Test, :stub}
      assert Keyword.fetch!(merged, :receive_timeout) == 1_000
      assert Keyword.fetch!(merged, :url) == "https://example.com"
    end
  end

  # `Application.put_env(key, nil)` is not the same as leaving the key unset:
  # a stored `nil` beats the `[]` default in `Application.get_env/3`, so
  # `Keyword.get(nil, :req_options)` would raise. The `|| []` in `merge/2` is
  # load-bearing, and this is what says so.
  describe "merge/2 reads a stored nil as absent" do
    # MUTATION: drop the `|| []`, leaving `Keyword.merge(configured, built)`.
    # Reddens as a raise, not a mismatch: `Keyword.merge(nil, …)` has no
    # matching clause. Merge order is irrelevant here.
    test "a nil :req_options yields the built options unchanged" do
      put_req_options(nil)

      assert ReqOptions.merge(@provider, method: :get) == [method: :get]
    end

    # MUTATION: drop the `[]` default from `Application.get_env(:brando,
    # provider, [])`. A missing key then yields `nil`, and `Keyword.get(nil,
    # :req_options)` raises before the `|| []` is ever reached.
    #
    # This is the mutation that *distinguishes* the two tests: it reddens this
    # one alone. Dropping the `|| []` reddens both, because with the key absent
    # `Keyword.get([], :req_options)` also returns `nil` — so the stored-nil
    # test above cannot stand in for this one, and neither is redundant. Two
    # routes to the same `nil`, two guards, one test each.
    test "an unset provider yields the built options unchanged" do
      # Restored, not merely deleted. `async: false` is not isolation — every
      # other test in this file reads the same key, and a `delete_env` with no
      # `on_exit` leaves the absence behind for whatever runs next. The suite
      # has already paid for this shape twice (see `with_config/2` in
      # `provider_client_test.exs`, and Phase 5's W4).
      original = Application.fetch_env(:brando, @provider)
      Application.delete_env(:brando, @provider)

      on_exit(fn ->
        case original do
          {:ok, prior} -> Application.put_env(:brando, @provider, prior)
          :error -> Application.delete_env(:brando, @provider)
        end
      end)

      assert ReqOptions.merge(@provider, method: :get) == [method: :get]
    end
  end

  # The other half of the `@doc`: what the merge does **not** stop. These are
  # not defects — the config author owns `runtime.exs` — but the doc names them
  # as reachable, and a doc that names specifics should be falsifiable.
  #
  # A keyword-list assertion cannot do that. Checking that `:auth` survives
  # `Keyword.merge/2` restates `Keyword.merge/2`, and reads as though the four
  # keys it happened to list were *the* four — which is the closed reading the
  # doc is being corrected for. The claim actually worth pinning is the
  # consequence: a configured `:auth` reaches **the wire** and displaces the
  # `authorization` header the caller built. That happens in a Req pipeline
  # step, not in this module, so only a round trip can see it.
  describe "merge/2 does not defend keys the built options omit" do
    # MUTATION: wrap the configured side in
    # `Keyword.take(configured || [], [:headers, :method, :url, :json])`, which
    # drops `:auth`; the stub then sees the built header and this reddens.
    #
    # It also goes red if **Req** changes underneath us — switch `auth/2` to
    # `put_new_header/3` (`req/steps.ex:236, 240, 244`) and the built header
    # survives instead. That is the drift this doc is exposed to and the reason
    # the assertion is on the header rather than on the keyword list: nothing
    # in this repo would otherwise notice.
    test "a configured :auth overwrites the authorization header on the wire" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer hijacked"]

        Req.Test.json(conn, %{"ok" => true})
      end)

      put_req_options(auth: {:bearer, "hijacked"}, plug: {Req.Test, __MODULE__})

      merged =
        ReqOptions.merge(@provider,
          method: :get,
          url: "https://example.com/videos",
          headers: [{"authorization", "Bearer built"}]
        )

      # The built header is still in the keyword list — the merge did defend
      # it. It is Req's auth step that overwrites it afterwards, which is
      # exactly why the keyword list is the wrong place to look.
      assert Keyword.fetch!(merged, :headers) == [{"authorization", "Bearer built"}]
      assert {:ok, %{status: 200}} = Req.request(merged)
    end
  end
end
