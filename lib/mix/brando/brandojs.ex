defmodule Mix.Brando.BrandoJS do
  @moduledoc false

  # Where an application's admin (`assets/backend`) takes `@brandocms/brandojs`
  # from. A released Brando pairs with the npm release of the same version. A
  # development version (`0.55.0-dev`) has no npm release, so its admin takes
  # the package from a Brando checkout through Yalc. That is also how Brando
  # itself is worked on against an application: Yalc copies the checkout, and
  # the backend's Vite plugin pulls each new `yalc publish`.

  @package "@brandocms/brandojs"
  @yalc_spec "file:.yalc/@brandocms/brandojs"
  @sections ~w(dependencies devDependencies)

  def package, do: @package

  @doc "The dependency spec a generated admin uses with Brando `version`."
  def spec(version \\ Brando.version()), do: if(development?(version), do: @yalc_spec, else: version)

  @doc "Whether `version` is a development version, which has no npm release."
  def development?(version) do
    match?({:ok, %Version{pre: ["dev" | _]}}, Version.parse(version))
  end

  @doc """
  Whether `spec` takes the package from a local source, a Yalc copy or a
  linked checkout, rather than from npm. That choice is the application's,
  and generators and upgrades keep it.
  """
  def local?(spec) when is_binary(spec), do: String.starts_with?(spec, ["file:", "link:"])
  def local?(_spec), do: false

  @doc "Whether `spec` takes the package from the admin's Yalc copy (`.yalc`)."
  def yalc?(spec) when is_binary(spec), do: String.starts_with?(spec, ["file:.yalc/", "link:.yalc/"])
  def yalc?(_spec), do: false

  @doc "The BrandoJS spec in a decoded package.json, or nil."
  def dependency(package) when is_map(package) do
    Enum.find_value(@sections, &get_in(package, [&1, @package]))
  end

  @doc "The first local BrandoJS spec in a decoded package.json's dependency sections, or nil."
  def local_dependency(package) when is_map(package) do
    package |> sections() |> Enum.map(&package[&1][@package]) |> Enum.find(&local?/1)
  end

  @doc "The sections (`dependencies`, `devDependencies`) of a decoded package.json that declare BrandoJS."
  def sections(package) when is_map(package) do
    Enum.filter(@sections, &is_map_key(package[&1] || %{}, @package))
  end

  @doc """
  Sets the BrandoJS dependency in package.json `contents` to `spec`, in each
  section that declares it, or in `dependencies` when none does. Key order is
  kept.
  """
  def put_spec(contents, spec) do
    package = Jason.decode!(contents, objects: :ordered_objects)

    sections =
      case Enum.filter(@sections, &(package[&1][@package] != nil)) do
        [] -> ["dependencies"]
        sections -> sections
      end

    sections
    |> Enum.reduce(package, fn section, package ->
      put_key(package, section, put_key(package[section] || Jason.OrderedObject.new([]), @package, spec))
    end)
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp put_key(%Jason.OrderedObject{values: values}, key, value) do
    values =
      if List.keymember?(values, key, 0),
        do: List.keyreplace(values, key, 0, {key, value}),
        else: values ++ [{key, value}]

    Jason.OrderedObject.new(values)
  end
end
