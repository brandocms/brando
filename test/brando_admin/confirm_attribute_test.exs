defmodule BrandoAdmin.ConfirmAttributeTest do
  # Nothing in the admin reads `phx-confirm`: a button carrying it acts on the
  # first click. Confirmations use `data-confirm` (assets/src/confirm.js) or the
  # ConfirmClick hook's `phx-confirm-click`; see the admin UI skill's
  # confirmations reference.
  use ExUnit.Case, async: true

  # Brando's own templates, the generators' templates that end up in apps, and
  # the E2E app's.
  @globs ["lib/**/*.{ex,heex}", "priv/templates/**/*.{ex,exs,heex,eex}", "e2e/lib/**/*.{ex,heex}"]

  # As a HEEx attribute (`=` may sit on the next line), a map key or a keyword.
  # `phx-confirm-click` and attributes that only end in `phx-confirm` pass.
  @dead ~r/(?<![\w-])(?:phx-confirm\s*=|"phx-confirm"\s*(?:=>|:)|phx_confirm\s*:)/

  test "the pattern finds every spelling of the attribute" do
    for spelling <- [
          ~s|phx-confirm="Sure?"|,
          ~s|phx-confirm={gettext("Sure?")}|,
          ~s|phx-confirm = {gettext("Sure?")}|,
          ~s|phx-confirm\n  ={gettext("Sure?")}|,
          ~s|%{"phx-confirm" => "Sure?"}|,
          ~s|["phx-confirm": "Sure?"]|,
          ~s|[phx_confirm: "Sure?"]|,
          ~s|rest={[phx_confirm: "Sure?"]}|
        ] do
      assert spelling =~ @dead, "missed: #{spelling}"
    end

    for spelling <- [
          ~s|phx-confirm-click="delete"|,
          ~s|data-confirm="Sure?"|,
          ~s|data-phx-confirm="Sure?"|,
          ~s|%{"phx-confirm-click" => "delete"}|,
          ~s|[phx_confirm_click: "delete"]|
        ] do
      refute spelling =~ @dead, "flagged: #{spelling}"
    end
  end

  test "no template uses the dead phx-confirm attribute" do
    offenders =
      for file <- Enum.flat_map(@globs, &Path.wildcard/1),
          source = File.read!(file),
          [{offset, _length}] <- Regex.scan(@dead, source, return: :index),
          do: "#{file}:#{line_number(source, offset)}"

    assert offenders == [], """
    `phx-confirm` does nothing in the admin. Use `data-confirm` (with
    `data-confirm-title`, `data-confirm-ok` and `data-confirm-destructive` as
    the action needs) or the ConfirmClick hook:

    #{Enum.join(offenders, "\n")}
    """
  end

  defp line_number(source, offset) do
    source |> binary_part(0, offset) |> String.split("\n") |> length()
  end
end
