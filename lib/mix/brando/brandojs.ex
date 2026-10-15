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

  @doc "The BrandoJS spec in a decoded package.json, or nil."
  def dependency(package) when is_map(package) do
    get_in(package, ["dependencies", @package]) || get_in(package, ["devDependencies", @package])
  end

  @doc "Sets the BrandoJS dependency in package.json `contents` to `spec`, leaving the rest of the text as it is."
  def put_spec(contents, spec) do
    Regex.replace(~r/("@brandocms\/brandojs"\s*:\s*)"[^"]*"/, contents, ~s(\\1"#{spec}"), global: false)
  end
end
