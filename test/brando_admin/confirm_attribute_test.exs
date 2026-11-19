defmodule BrandoAdmin.ConfirmAttributeTest do
  # Nothing in the admin reads `phx-confirm`: a button carrying it acts on the
  # first click. Confirmations use `data-confirm` (assets/src/confirm.js) or the
  # ConfirmClick hook's `phx-confirm-click`; see the admin UI skill's
  # confirmations reference.
  use ExUnit.Case, async: true

  # Rewritten with a working confirmation in #3708; drop it once that is merged.
  @pending ["lib/brando_admin/live/sites/site_live.ex"]

  test "no template uses the dead phx-confirm attribute" do
    offenders =
      for file <- Path.wildcard("lib/**/*.{ex,heex}"),
          file not in @pending,
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ ~r/\bphx-confirm=/,
          do: "#{file}:#{number}: #{String.trim(line)}"

    assert offenders == [], """
    `phx-confirm` does nothing in the admin. Use `data-confirm` (with
    `data-confirm-title`, `data-confirm-ok` and `data-confirm-destructive` as
    the action needs) or the ConfirmClick hook:

    #{Enum.join(offenders, "\n")}
    """
  end
end
