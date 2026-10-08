defmodule Brando.Doctor.Context do
  @moduledoc """
  Where the doctor runs, passed to every `Brando.Doctor.Check`.

    * `:mode` — `:mix` for `mix brando.doctor`, `:admin` for the Utilities card.
    * `:source?` — whether the project's source tree is at hand. `false` in a
      release, where checks that read `lib/` or `assets/` are skipped.
    * `:root` — the project directory (the working directory by default).
    * `:prefix` — the tenant prefix the checks run under in the admin.
    * `:environments` — `[{label, prefix}]` the content checks cover: every
      environment of every active site from the terminal when tenancy is on,
      the current one in the admin, `[{nil, nil}]` without tenancy. Use
      `each_environment/2` rather than reading it.
    * `:oban` — the application's Oban configuration. The mix task starts Oban
      without queues so nothing runs; this is what it would run with.
    * `:now` — the time to measure ages against.
    * `:offline?` — whether checks must not reach the network. The Versions
      check asks a git remote for its latest commit only from the terminal,
      and not with `mix brando.doctor --offline`.
  """

  alias Brando.Tenant

  @type t :: %__MODULE__{
          mode: :mix | :admin,
          source?: boolean(),
          root: Path.t(),
          prefix: String.t() | nil,
          environments: [{String.t() | nil, String.t() | nil}],
          locale: String.t(),
          oban: keyword(),
          now: DateTime.t(),
          offline?: boolean()
        }

  defstruct mode: :mix,
            source?: true,
            root: nil,
            prefix: nil,
            environments: [{nil, nil}],
            locale: "en",
            oban: [],
            now: nil,
            offline?: false

  @doc "Builds a context; every field can be given in `opts`."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    mode = Keyword.get(opts, :mode, :mix)
    prefix = Keyword.get_lazy(opts, :prefix, &Tenant.current_prefix/0)

    %__MODULE__{
      mode: mode,
      source?: Keyword.get_lazy(opts, :source?, &source_available?/0),
      root: Keyword.get_lazy(opts, :root, &File.cwd!/0),
      prefix: prefix,
      environments: Keyword.get_lazy(opts, :environments, fn -> environments(mode, prefix) end),
      locale: Keyword.get_lazy(opts, :locale, fn -> Gettext.get_locale(Brando.Gettext) end),
      oban: Keyword.get_lazy(opts, :oban, &oban_config/0),
      now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0),
      offline?: Keyword.get(opts, :offline?, false)
    }
  end

  @doc """
  Runs `fun` once in each of the context's environments and returns
  `[{label, result}]`. `label` is `nil` without tenancy.
  """
  @spec each_environment(t(), (-> result)) :: [{String.t() | nil, result}] when result: var
  def each_environment(%__MODULE__{environments: environments}, fun) do
    Enum.map(environments, fn
      {label, nil} -> {label, fun.()}
      {label, prefix} -> {label, Tenant.with_prefix(prefix, fun)}
    end)
  end

  @doc "Prefixes `item` with the environment's label, when there is one."
  @spec label_item(String.t() | nil, String.t()) :: String.t()
  def label_item(nil, item), do: item
  def label_item(label, item), do: "[#{label}] #{item}"

  @doc """
  Whether the project's source is at hand: false in a release, where Mix
  is not loaded.
  """
  @spec source_available?() :: boolean()
  def source_available? do
    is_nil(System.get_env("RELEASE_NAME")) and Code.ensure_loaded?(Mix.Project)
  end

  defp environments(:mix, _prefix) do
    if Tenant.enabled?() do
      for site <- Tenant.Registry.list_sites(),
          site.status == :active,
          environment <- Enum.sort_by(site.environments, & &1.id),
          do: {"#{site.key}/#{environment.key}", Tenant.prefix(site, environment)}
    else
      [{nil, nil}]
    end
  end

  defp environments(_mode, prefix), do: [{nil, prefix}]

  defp oban_config, do: Application.get_env(:brando, Oban) || Brando.Supervisor.oban_config()
end
