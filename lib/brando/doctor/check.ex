defmodule Brando.Doctor.Check do
  @moduledoc """
  The behaviour of one `mix brando.doctor` check.

  A check reads and reports; it never changes anything. Return a
  `Brando.Doctor.Result` from `run/1`:

      defmodule MyApp.Doctor.SearchIndex do
        use Brando.Doctor.Check

        @impl true
        def id, do: "search_index"

        @impl true
        def label, do: "Search index"

        @impl true
        def run(_context) do
          case MyApp.Search.stale_count() do
            0 -> ok("up to date")
            n -> warning("\#{n} entries not indexed", fix: "run mix my_app.reindex", items: MyApp.Search.stale_titles())
          end
        end
      end

  Register it in config; Brando's own checks run first:

      config :brando, Brando.Doctor, checks: [MyApp.Doctor.SearchIndex]

  `use Brando.Doctor.Check` imports `ok/2`, `warning/2`, `error/2` and
  `skipped/2` from `Brando.Doctor.Result`. A check that reads the project's
  source tree (files under `lib/` or `assets/`) returns `true` from
  `needs_source?/0`; it is skipped, with a note, in a release.

  `label/0` is shown in the admin's Utilities card as well, so it may be
  translated with the application's Gettext backend. The doctor runs checks in
  the admin user's locale there, and in English in the terminal.
  """

  alias Brando.Doctor.Context
  alias Brando.Doctor.Result

  @doc "A stable key for `--json` and tests, like `\"migrations\"`."
  @callback id() :: String.t()

  @doc "What is checked, as a short name: \"Migrations\"."
  @callback label() :: String.t()

  @doc "Runs the check."
  @callback run(Context.t()) :: Result.t()

  @doc "Whether the check reads the project's source tree. Defaults to `false`."
  @callback needs_source?() :: boolean()

  @optional_callbacks needs_source?: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Brando.Doctor.Check

      import Brando.Doctor.Result,
        only: [ok: 1, ok: 2, warning: 1, warning: 2, error: 1, error: 2, skipped: 1, skipped: 2]

      @impl Brando.Doctor.Check
      def needs_source?, do: false

      defoverridable needs_source?: 0
    end
  end
end
