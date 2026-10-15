# The packaged smoke's admin assets, around `mix brando.assets.setup`:
#
#   pin VERSION TARBALL     the generated admin pins BrandoJS VERSION from npm;
#                           keep that pin and point pnpm at the packed TARBALL,
#                           which no registry has, with a pnpm override
#   verify VERSION TARBALL  BrandoJS VERSION came from TARBALL, and nothing in
#                           the app came from Yalc
[action, version, tarball] = System.argv()
package = "@brandocms/brandojs"
backend = "assets/backend/package.json"

case action do
  "pin" ->
    json = backend |> File.read!() |> Jason.decode!(objects: :ordered_objects)
    ^version = json["dependencies"][package] || raise("#{backend} does not pin #{package} #{version}")

    # Sets `key` in an ordered object, in place when present.
    put = fn object, key, value ->
      values = (object || Jason.OrderedObject.new([])).values

      if List.keymember?(values, key, 0),
        do: Jason.OrderedObject.new(List.keyreplace(values, key, 0, {key, value})),
        else: Jason.OrderedObject.new(values ++ [{key, value}])
    end

    overrides = put.(json["pnpm"]["overrides"], package, "file:" <> tarball)
    json = put.(json, "pnpm", put.(json["pnpm"], "overrides", overrides))
    File.write!(backend, Jason.encode!(json, pretty: true) <> "\n")
    IO.puts("#{backend} pins #{package} #{version}; pnpm overrides it with #{tarball}")

  "verify" ->
    ^version = Jason.decode!(File.read!(backend))["dependencies"][package]

    installed = Path.join(["assets/backend/node_modules", package, "package.json"])
    %{"version" => ^version} = installed |> File.read!() |> Jason.decode!()

    # pnpm records the integrity of what it installed; it must be the tarball's.
    integrity = "sha512-" <> Base.encode64(:crypto.hash(:sha512, File.read!(tarball)))
    lock = File.read!("assets/backend/pnpm-lock.yaml")

    unless String.contains?(lock, integrity),
      do: raise("pnpm-lock.yaml has no #{package} with #{tarball}'s integrity #{integrity}")

    yalc =
      for dir <- [".", "assets/backend", "assets/frontend"],
          name <- [".yalc", "yalc.lock"],
          path = Path.join(dir, name),
          File.exists?(path),
          do: path

    store = Path.join(Mix.Project.build_path(), "brando_yalc")
    if File.exists?(store), do: raise("Yalc store #{store} exists")
    if yalc != [], do: raise("Yalc state in the app: #{Enum.join(yalc, ", ")}")

    IO.puts("#{package} #{version} installed from #{tarball}; no Yalc copy, lock or store")
end
