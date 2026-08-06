# Test Review: Phase 3 form-audit test changes

## Summary

The gallery suite is the strongest work here: it handled the `config :logger, level: :error`
trap explicitly, and the merge/dedupe tests are genuinely sensitive to their fixes. The two
brand-new `Form` suites are weaker than their comments claim: `empty_params_errors_test.exs`
contains **five tests, none of which fail if the fix is reverted**, and two of the four
`addon_statuses_test.exs` tests are insensitive to the change they document.
One async-safety violation is a real cross-test hazard.

## Iron Law Violations

- **Law 1 (async by default) — inverted violation:**
  `test/brando_admin/components/form/input/options_test.exs:5` declares `async: true` while
  `:28` mutates `Application.put_env(:brando, :languages, ...)`. Global app env is shared
  across the whole VM, so any *other* async test that reads `Brando.config(:languages)`
  (Input.Select / MultiSelect / radios render tests, blueprint language validation,
  `Brando.I18n`) can observe `[[value: "zz", text: "Testish"]]` for the duration. The
  `try/after` restores it but does not serialise it. **Fix: `async: false`.**

## Issues Found

### Critical (BLOCKER)

- [ ] **`empty_params_errors_test.exs` — all 5 tests pass against the pre-fix code.**
      The change under test is the removal of `Map.put(:action, :validate)` from
      `assign_form/1`, `assign_refreshed_form/1` and the `refresh_entry` path. Tests at
      `:32`, `:39`, `:50`, `:61` never touch `BrandoAdmin.Components.Form` at all — they
      assert `Phoenix.Component.used_input?/1` semantics, i.e. they test Phoenix, not this
      diff. Test `:76` is the only one that drives `assign_refreshed_form/1`, and its three
      assertions (`params == %{}`, `%Changeset{} = source`, `refute used_input?`) all hold
      **identically with the forced action still in place**.
      The one assertion sensitive to the change is missing:
      ```elixir
      assert socket.assigns.form.source.action == nil
      ```
      at `:88`. Without it, the forced action can be reintroduced anywhere in the pipeline
      and this file stays green. Add it to `:76` and to a companion case driving
      `assign_form/1`.
      (The `used_input?` tests are still worth keeping as *documentation* of why the removal
      is safe — but they must not be counted as regression coverage.)

- [ ] **`options_test.exs:5` — `async: true` with `Application.put_env`.** See Iron Law
      above. This is a live flake generator, not a style nit.

### Warnings

- [ ] **`addon_statuses_test.exs:78` — "static statuses survive a re-render" cannot fail.**
      `before` is snapshotted *from the socket itself* after mount, then compared to the same
      socket's assigns after `re_render/2`. If `assign_addon_statuses/1` were deleted outright
      the assigns would simply persist and the test would still pass. It also passes pre-fix,
      because the plain `assign/2` version recomputed the *same* values. Make it sensitive by
      asserting against the schema-derived truth (as `:96` correctly does for `has_meta?`),
      e.g. `assert socket.assigns.has_blocks? == Brando.Pages.Page.has_trait(Brando.Trait.Blocks)`,
      or by poisoning the assign before `re_render` and asserting `assign_new` did *not*
      clobber the poison.

- [ ] **`addon_statuses_test.exs:75` — `all_transformers_received? == true` is vacuous.**
      `Brando.Pages.Page` declares no transformers, so `extract_transformers/1` returns `[]`
      and the pre-fix `assign_transformer_statuses/1` also set this to `true`
      (`form.ex:1478`). Only the `transformer_changesets` assertion at `:74` is fix-sensitive.
      To make both halves meaningful the test needs a blueprint (or a stubbed
      `form_blueprint`) that actually declares a transformer, so pre-fix would reset
      `all_transformers_received?` from `true` back to `false`. As written the comment at
      `:64` ("modelled directly here so the test does not need a blueprint") is exactly what
      costs the test its teeth on that assertion.

- [ ] **`addon_statuses_test.exs:105` — `has_alternates?` test is not a regression test for
      this diff.** `has_alternates?` remained a plain `assign` (`form.ex:1460`), so this
      passes identically pre- and post-fix. Fine as a forward guard; should not be reported
      as covering E1.

- [ ] **`form_component_resolver_test.exs:26` — the rewrite no longer defends the property.**
      The stated invariant is "no compile-time dependency from Blueprint onto admin component
      modules". The rewritten assertion (`:38`) only checks the resolved value, which is the
      new happy path — identical in content to
      `component_resolution_test.exs:18`. The no-compile-dependency claim now lives entirely
      in a comment citing a `mix xref graph` run the suite never repeats. A test rewritten to
      match the change has stopped protecting anything. Concrete replacement:
      ```elixir
      refute BrandoAdmin.Components.Form.Input.Vars in
               Enum.map(Brando.Content.TableTemplate.__info__(:compile)[:source] |> ..., & &1)
      ```
      is awkward; the clean version is a `Mix.Tasks.Xref`-backed assertion, e.g.
      ```elixir
      test "no compile-time edge from Blueprint to admin components" do
        {_, deps} = Mix.Tasks.Xref.calls() |> ... # or read the manifest
        refute {Brando.Content.TableTemplate, BrandoAdmin.Components.Form.Input.Vars, :compile} in deps
      end
      ```
      If that is judged too fragile, the minimum acceptable substitute is a comment-free
      assertion that `ComponentResolver.resolve/1` is what produced the value (e.g. resolve a
      token the Blueprint does *not* name), plus a CI xref check outside ExUnit. Either way,
      do not leave the property asserted only in prose.

- [ ] **`addon_statuses_test.exs:13` / `empty_params_errors_test.exs:13` /
      `gallery_test.exs:18` — `use ExUnit.Case, async: false` immediately followed by
      `use Brando.ConnCase`.** `Brando.ConnCase` is an `ExUnit.CaseTemplate` and already
      brings `ExUnit.Case` in. The doubled `use` makes the effective `async` value depend on
      which `use` wins, and `ConnCase.setup_sandbox/1` keys its sandbox mode on `tags[:async]`.
      Prefer the single `use Brando.ConnCase, async: false`.

- [ ] **`gallery_test.exs:329` — fixture shape diverges from production.** The delivery path
      sends `new_image: %{image_id: ..., image: ...}` (a bare map, `form.ex:607`); the test
      passes a `%GalleryObject{}` struct. It currently works because `same_media?/2` uses
      `Map.get/2` (`galleries.ex:179`), but the test would keep passing if that helper were
      tightened to a `%GalleryObject{}` pattern while production kept sending maps. Use the
      map form, matching `form.ex:607`.

### Coverage Gaps — highest regression risk first

1. **`form.ex:614-619`, the `image.status != :processed` gate on `processing_images` — the
   riskiest untested change in this diff.** A wrong branch here is silent and permanent: an
   image id added to `processing_images` that never receives an `[:image, :updated]`
   broadcast leaves the entry form showing a spinner forever, with no error anywhere. It is
   also the cheapest thing in the diff to test — `gallery_test.exs` already has
   `entry_form_socket/1` and `deliver_gallery_image/2`:
   ```elixir
   test "an already-processed delivery does not leave a stuck processing entry", ctx do
     processed = Factory.insert(:image, creator: ctx.user, status: :processed)
     socket = ctx |> entry_form_socket() |> deliver_gallery_image(processed)
     assert socket.assigns.processing_images == []
   end

   test "an unprocessed delivery is tracked until its broadcast arrives", ctx do
     pending = Factory.insert(:image, creator: ctx.user, status: :unprocessed)
     socket = ctx |> entry_form_socket() |> deliver_gallery_image(pending)
     assert socket.assigns.processing_images == [pending.id]

     {:ok, socket} = Form.update(%{action: :image_processed, image_id: pending.id}, socket)
     assert socket.assigns.processing_images == []
   end
   ```
   Two tests, existing helpers, no new harness. This should land before the others.

2. **`block_field.ex:657` / `:675` — `connected?/1` gating on PubSub subscribe/broadcast.**
   Untested. Risk is lower than (1) because the failure mode is a wasted subscription on a
   dead render rather than corrupted UI state, but `:675` gating a *broadcast* means a
   regression silently stops notifying other clients. Testable without a full LiveView by
   asserting on a socket with `transport_pid: nil` vs a set pid and `refute_receive` /
   `assert_receive` on a subscribed test process.

3. **`form.ex:3993` / `:4785` / `:3550` — the `"brando:image:<id>"` subscribe calls.** No
   `unsubscribe` counterpart exists anywhere in `form.ex` (grep confirms), so every delivered
   image permanently subscribes the parent LiveView. Whether that is the intended design or a
   leak is worth confirming; either way it is untested and belongs in the Phase 4 harness, not
   a unit test.

4. **`block.ex` conditional `@fragments` / `@containers` / `@palette_options` assigns.**
   Untested. Lowest risk of the three flagged: a missed assign surfaces immediately as a
   `KeyError` in render, which existing block e2e coverage would catch.

5. **`galleries.ex:165-173` `fresher?/2` — the `updated_at: nil` clauses (`:167`, `:168`) have
   no test.** `gallery_test.exs:213` covers `:gt`, `:lt` and the tie, but a nil timestamp
   (an unsaved image struct) takes an untested branch that decides which copy survives.

### Suggestions

- [ ] `component_resolution_test.exs:31` — `assert Enum.all?(fields(form), &(&1.component == nil or is_atom(&1.component)))`
      is trivially true for every possible value except a binary/tuple; `nil` is itself an
      atom, so the left disjunct is redundant. What the test means to assert is "no field
      still holds an unresolved token", which is better written as a positive check that no
      component value is in `ComponentResolver`'s token list.
- [ ] `options_test.exs:40` — `assert Options.expand(:languages) == Options.expand(:languages)`
      asserts a pure function is pure; it cannot detect memoization (a cache returns the same
      value too). To actually pin "does not memoize", the second `put_env` must happen
      *after* a first `expand/1` call and assert the new value is observed — which the
      `try` block at `:33` already does. Drop `:40`.
- [ ] `empty_params_errors_test.exs:29` — `empty_params_form/1` is defined but only used by
      the test at `:39`; `:50` and `:61` rebuild the changeset inline. Route all three through
      the helper.
- [ ] `addon_statuses_test.exs:44` — `re_render/2` omits `entry_id` and `header`, which the
      mount call at `:30` supplies. If the generic `update/2` clause ever starts requiring
      them the divergence will read as a production bug. Build the props map once and
      `Map.merge` the presence diff onto it.
