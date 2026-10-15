defmodule Brando.EuropaCSS do
  @moduledoc """
  The native EuropaCSS packages the admin's CSS builds with, against an
  application's `assets/backend`, for `mix brando.doctor` and
  `mix brando.migrate55`.

  The versions are the ones Brando's backend template pins, so both follow
  the template. A backend still on the legacy `@brandocms/europacss` PostCSS
  plugin, on a Yalc copy of the Vite plugin from before it was published, or
  on other versions is brought to them by `mix brando.gen.backend --upgrade`.
  """

  use Gettext, backend: Brando.Gettext

  @packages ~w(@brandocms/vite-plugin-europacss @brandocms/europacss-cli)
  # The legacy PostCSS plugin, under its current and its earlier name.
  @legacy ~w(@brandocms/europacss @univers-agency/europacss)

  @template "priv/templates/brando.install/assets/backend/package.json"

  @type problem ::
          {:legacy, String.t(), String.t()}
          | {:missing, String.t()}
          | {:local, String.t(), String.t()}
          | {:version, String.t(), String.t()}
          | {:not_installed, String.t()}
          | {:installed, String.t(), String.t() | nil}

  @doc "The versions Brando's backend template pins, by package."
  @spec pins() :: %{String.t() => String.t()}
  def pins do
    :brando
    |> Application.app_dir(@template)
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("devDependencies")
    |> Map.take(@packages)
  end

  @doc """
  What keeps a decoded backend `package.json` from Brando's native EuropaCSS
  build, or `[]`:

    * `{:legacy, package, spec}` - the legacy PostCSS plugin,
      `@brandocms/europacss` (`@univers-agency/europacss` before that), is a
      dependency
    * `{:missing, package}` - a pinned package is not a dependency
    * `{:local, package, spec}` - installed from a Yalc copy or a path
    * `{:version, package, spec}` - declared at another version than the pin
  """
  @spec package_problems(map()) :: [problem()]
  def package_problems(package) when is_map(package) do
    pins = pins()
    legacy = for name <- @legacy, spec = dependency(package, name), do: {:legacy, name, spec}

    legacy ++
      Enum.flat_map(@packages, fn name ->
        pin = pins[name]

        case dependency(package, name) do
          nil -> [{:missing, name}]
          "file:" <> _ = spec -> [{:local, name, spec}]
          "link:" <> _ = spec -> [{:local, name, spec}]
          ^pin -> []
          spec -> [{:version, name, spec}]
        end
      end)
  end

  @doc """
  What `node_modules` in `backend` (an `assets/backend` directory) has of the
  pinned packages, or `[]`: `{:not_installed, package}`, or
  `{:installed, package, version}` for another version than the pin, as
  after a `package.json` change without a `pnpm install`.
  """
  @spec install_problems(Path.t()) :: [problem()]
  def install_problems(backend) do
    pins = pins()

    Enum.flat_map(@packages, fn name ->
      pin = pins[name]

      case installed_version(backend, name) do
        :none -> [{:not_installed, name}]
        ^pin -> []
        version -> [{:installed, name, version}]
      end
    end)
  end

  defp installed_version(backend, name) do
    with {:ok, body} <- File.read(Path.join([backend, "node_modules", name, "package.json"])),
         {:ok, %{} = manifest} <- Jason.decode(body) do
      manifest["version"]
    else
      _ -> :none
    end
  end

  @doc "A problem as a line of text."
  @spec describe(problem()) :: String.t()
  def describe({:legacy, name, spec}),
    do: dgettext("doctor", "builds with the legacy %{package} %{version}", package: name, version: spec)

  def describe({:missing, name}), do: dgettext("doctor", "%{package} is not a dependency", package: name)

  def describe({:local, name, spec}),
    do: dgettext("doctor", "%{package} from %{source}, not npm", package: name, source: spec)

  def describe({:version, name, spec}),
    do: dgettext("doctor", "%{package} %{version}, Brando's is %{pin}", package: name, version: spec, pin: pins()[name])

  def describe({:not_installed, name}), do: dgettext("doctor", "%{package} not installed", package: name)

  def describe({:installed, name, version}) do
    dgettext("doctor", "%{package} %{version} installed, package.json has %{pin}",
      package: name,
      version: version || "-",
      pin: pins()[name]
    )
  end

  defp dependency(package, name) do
    get_in(package, ["devDependencies", name]) || get_in(package, ["dependencies", name])
  end
end
