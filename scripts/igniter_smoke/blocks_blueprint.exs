# Gives the generated Product Blueprint blocks and an image asset, as most
# content types have. Brando's data migrations look these up from the
# application's current code, so they meet tables that a database migrated
# from scratch does not have yet (fresh_migrations.exs).
path = "lib/igniter_smoke/catalog/product.ex"
blueprint = File.read!(path)

replace = fn blueprint, from, to ->
  true = String.contains?(blueprint, from)
  String.replace(blueprint, from, to, global: false)
end

blueprint =
  blueprint
  |> replace.("  trait :timestamped\n", "  trait :timestamped\n  trait :blocks\n")
  |> replace.("    attribute :slug, :slug, required: true\n  end\n", """
      attribute :slug, :slug, required: true
    end

    assets do
      asset :cover, :image, cfg: :default
    end

    relations do
      relation :blocks, :has_many, module: :blocks
    end
  """)
  |> replace.(
    ~s|      default_params %{"status" => "draft"}\n|,
    ~s|      default_params %{"status" => "draft"}\n      blocks :blocks, label: t("Blocks")\n|
  )
  |> replace.(
    ~s|          input :status, :status, label: t("Status")\n|,
    ~s|          input :status, :status, label: t("Status")\n          input :cover, :image, label: t("Cover")\n|
  )

File.write!(path, blueprint)
