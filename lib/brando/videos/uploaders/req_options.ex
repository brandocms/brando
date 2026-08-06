defmodule Brando.Videos.Uploaders.ReqOptions do
  @moduledoc """
  The one owner of the video providers' `:req_options` precedence rule.

  Mux, Bunny and Cloudflare build genuinely different requests — Basic auth vs
  an `AccessKey` header vs a Bearer token, two URL shapes, and two different
  answers to missing credentials — so their `api_request` functions are not one
  function with cosmetic differences and are not collapsed here.

  What *was* byte-identical across all three, and therefore what could drift in
  one of them without anyone noticing, is this merge. That is what this module
  owns.
  """

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
  ones with the sharpest consequences against **req 0.7.2**:

    * `:redirect_trusted` — `remove_credentials_if_untrusted(request, true, _)`
      hands the request back untouched (`req/steps.ex:1571`), disabling
      cross-host credential stripping outright. On a doc about config seams
      that can unset credentials, this is the sharpest one available.
    * `:auth` — Req's auth step writes with `Req.Request.put_header/3`, not
      `put_new_header/3` (`req/steps.ex:236, 240, 244`), so
      `req_options: [auth: {:bearer, …}]` overwrites the `authorization` header
      the provider just built. Bunny's credential is an `AccessKey` header
      rather than `authorization`, so there it lands alongside instead.
    * `:form` / `:form_multipart` — `encode_body/1` tests both **before**
      `:json` (`req/steps.ex:486, 490` vs `:497`), so a configured `form:`
      replaces the body all three providers build.
    * `:json` — Bunny's GET and DELETE build no body (`bunny.ex:422, 428`), so
      a configured `json:` attaches one where there should be none.
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

  ## `nil` is not absent

  Reads `nil` as absent as well as unset: `Application.put_env(key, nil)` is not
  the same as not setting it, and a config-restore helper that stores `nil`
  otherwise beats the `[]` default.
  """
  @spec merge(module(), keyword()) :: keyword()
  def merge(provider, built_opts) do
    configured =
      :brando
      |> Application.get_env(provider, [])
      |> Keyword.get(:req_options)

    Keyword.merge(configured || [], built_opts)
  end
end
