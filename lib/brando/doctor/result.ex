defmodule Brando.Doctor.Result do
  @moduledoc """
  What one `Brando.Doctor.Check` found.

    * `:status` — `:ok`, `:warning`, `:error`, or `:skipped` when the check
      could not run here (a release without the source tree, say).
    * `:summary` — one short line: "up to date", "2 configs changed".
    * `:fix` — what to do about it, when the status is not `:ok`. A command
      or a place in the admin; the doctor never runs it.
    * `:link` — `{admin_live_view_or_path, label}`, the admin screen that
      fixes it. The Utilities card shows it as a button.
    * `:items` — the affected things, listed by `mix brando.doctor --verbose`.

  `:check`, `:id` and `:label` are filled in by `Brando.Doctor.run/1`.
  Build results with `ok/2`, `warning/2`, `error/2` and `skipped/2`, which take
  `:fix`, `:link` and `:items` as options.
  """

  @type status :: :ok | :warning | :error | :skipped
  @type link :: {module() | String.t(), String.t()}
  @type t :: %__MODULE__{
          check: module() | nil,
          id: String.t() | nil,
          label: String.t() | nil,
          status: status(),
          summary: String.t(),
          fix: String.t() | nil,
          link: link() | nil,
          items: [String.t()]
        }

  defstruct check: nil, id: nil, label: nil, status: :ok, summary: "", fix: nil, link: nil, items: []

  @statuses [:ok, :warning, :error, :skipped]

  @doc "All is well."
  @spec ok(String.t(), keyword()) :: t()
  def ok(summary, opts \\ []), do: build(:ok, summary, opts)

  @doc "Works, but should be looked at. Fails `mix brando.doctor --strict`."
  @spec warning(String.t(), keyword()) :: t()
  def warning(summary, opts \\ []), do: build(:warning, summary, opts)

  @doc "Broken or about to break. Fails `mix brando.doctor`."
  @spec error(String.t(), keyword()) :: t()
  def error(summary, opts \\ []), do: build(:error, summary, opts)

  @doc "Could not run here, and says why."
  @spec skipped(String.t(), keyword()) :: t()
  def skipped(summary, opts \\ []), do: build(:skipped, summary, opts)

  @doc "The more serious of two statuses."
  @spec worst(status(), status()) :: status()
  def worst(a, b), do: if(rank(a) >= rank(b), do: a, else: b)

  @doc "The statuses in order, from fine to broken."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  defp rank(:error), do: 3
  defp rank(:warning), do: 2
  defp rank(:ok), do: 1
  defp rank(:skipped), do: 0

  defp build(status, summary, opts) do
    %__MODULE__{
      status: status,
      summary: summary,
      fix: opts[:fix],
      link: opts[:link],
      items: Enum.map(opts[:items] || [], &to_string/1)
    }
  end
end
