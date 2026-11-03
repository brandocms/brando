defmodule Brando.Videos.Uploaders.ReqOptions do
  @moduledoc """
  The one owner of the video providers' `:req_options` precedence rule.

  Mux, Bunny and Cloudflare build genuinely different requests — Basic auth vs
  an `AccessKey` header vs a Bearer token, two URL shapes, and two different
  answers to missing credentials — so their `api_request` functions are not one
  function with cosmetic differences and are not collapsed here.

  What *was* byte-identical across all three, and therefore what could drift in
  one of them without anyone noticing, is this merge. That is what this module
  owns, with the timeouts a provider's DELETE gets (see `merge/2`).
  """

  @delete_connect_timeout 5_000
  @delete_receive_timeout 10_000

  @doc """
  Puts `provider`'s configured `:req_options` **underneath** `built_opts`.

  ## What this defends

  Exactly the keys `built_opts` names, and nothing more. All three providers
  build `:method`, `:url` and `:headers` (plus `:json` on a body), so a
  configured `req_options: [headers: …]`, `[url: …]` or `[method: …]` loses to
  the provider — a config seam that can unset credentials is a config seam that
  will. What the seam is *for* is the transport: a test points it at a
  `Req.Test` stub so the request a provider builds can be asserted without a
  network (see `test/brando/videos/provider_client_test.exs`), and nothing
  about that needs the power to rewrite the request itself.

  ## What still reaches past it

  The rule first, because the rule is the whole answer: this is a
  `Keyword.merge/2` and **not an allowlist**, so *any* configured key the built
  options do not name passes straight through to `Req.request/1`. That includes
  options Req has not shipped yet — a new one is reachable the day it lands,
  without a change here.

  What follows is therefore a list of **examples**, not a set. These are the
  ones with the sharpest consequences against **req 0.7.5**:

    * `:redirect_trusted` — `remove_credentials_if_untrusted(request, true, _)`
      hands the request back untouched (`req/steps.ex:1582`), disabling
      cross-host credential stripping outright. On a doc about config seams
      that can unset credentials, this is the sharpest one available.

      Worth knowing which providers it exposes. **Mux and Cloudflare** depend on
      Req's stripping, because their credential is an `authorization` header and
      that is one of the two things Req removes; setting `redirect_trusted: true`
      re-arms cross-host forwarding for both. **Bunny does not**, and not
      because its credential is safer — the opposite. Its `AccessKey` header was
      never covered by that stripping, so it carries `redirect: false` in its
      built options instead, which this merge cannot override. The provider with
      the weaker credential shape ended up with the stronger guarantee.
    * `:auth` — Req's auth step writes with `Req.Request.put_header/3`, not
      `put_new_header/3` (`req/steps.ex:236, 240, 244`), so
      `req_options: [auth: {:bearer, …}]` overwrites the `authorization` header
      the provider just built. Bunny's credential is an `AccessKey` header
      rather than `authorization`, so there it lands alongside instead.
    * `:form` / `:form_multipart` — `encode_body/1` tests both **before**
      `:json` (`req/steps.ex:478, 482` vs `:489`), so a configured `form:`
      replaces the body all three providers build.
    * `:json` — Bunny's GET and DELETE build no body (the `:get` and `:delete`
      branches of `Brando.Videos.Uploaders.Bunny`'s `api_request/3`), so a
      configured `json:` attaches one where there should be none. Cited by
      function because the last version of this line cited two interior line
      numbers that a comment added to `bunny.ex` in the same commit moved.
    * `:plug` / `:adapter` — replace the transport outright.
    * `:connect_options` / `:finch` — proxy and TLS verification: the same
      reach as `:plug`, by a longer route.
    * `:params` — appended to the query string.
    * `:into`, `:retry`, `:redirect`, `:decode_body`, `:receive_timeout`, and
      the rest of Req's option surface.

  `:base_url` is one of the few that is genuinely inert, and only because all
  three providers build absolute URLs: `put_base_url/1` no-ops when the URL
  already has a scheme (`req/steps.ex:123`).

  An allowlist was considered and declined. It is a library-visible behaviour
  change, and the actor here is the config author, who already owns
  `runtime.exs` — the merge order is a guard against accident, not against the
  operator.

  ## A DELETE's timeouts

  A provider's DELETE, which only its `delete_remote/1` sends, gets short
  timeouts: 5 seconds to connect and 10 to receive, which also caps the
  whole response (`:request_timeout`). The soft-delete purger asks each
  provider to delete its expired videos within one 30-second deadline for
  every schema and environment (`Brando.Worker.SoftDeletePurger`); left to
  Req, a provider that accepts the connection and never answers holds the
  call for 15 seconds a chunk, with no limit on the whole. A delete that
  times out is a transport error, so the purge keeps the row for the next
  run and asks that provider nothing more this run
  (`Brando.SoftDelete.Query.as_one_run/1`). A delete the provider made after
  the call gave up is found gone next time, which every provider takes as
  done. The retry of a delete with `delete_remote_on: :on_delete`
  (`Brando.Worker.VideoRemoteDelete`) sends the same request.

  Set them per provider, in milliseconds, beside `:req_options`:

      config :brando, Brando.Videos.Uploaders.Mux,
        delete_connect_timeout: 5_000,
        delete_receive_timeout: 10_000

  They win over the same keys in `:req_options`, which tune the provider's
  other calls, and a configured `:connect_options` keeps its other entries.
  With a `:finch` pool configured, the pool's own `conn_opts` set the
  connect timeout.

  ## `nil` is not absent

  Reads `nil` as absent as well as unset: `Application.put_env(key, nil)` is not
  the same as not setting it, and a config-restore helper that stores `nil`
  otherwise beats the `[]` default.
  """
  @spec merge(module(), keyword()) :: keyword()
  def merge(provider, built_opts) do
    config = Application.get_env(:brando, provider, [])
    configured = Keyword.get(config, :req_options) || []

    configured
    |> put_delete_timeouts(built_opts[:method], config)
    |> Keyword.merge(built_opts)
  end

  defp put_delete_timeouts(opts, :delete, config) do
    connect_timeout = Keyword.get(config, :delete_connect_timeout, @delete_connect_timeout)
    receive_timeout = Keyword.get(config, :delete_receive_timeout, @delete_receive_timeout)

    opts
    |> Keyword.merge(receive_timeout: receive_timeout, request_timeout: receive_timeout)
    |> put_connect_timeout(connect_timeout)
  end

  defp put_delete_timeouts(opts, _method, _config), do: opts

  # Req refuses `:connect_options` beside a `:finch` pool.
  defp put_connect_timeout(opts, timeout) do
    if Keyword.has_key?(opts, :finch),
      do: opts,
      else: Keyword.put(opts, :connect_options, Keyword.put(opts[:connect_options] || [], :timeout, timeout))
  end
end
