defmodule Brando.Sites.SiteTest do
  use ExUnit.Case, async: true

  alias Brando.Sites.Site

  @valid_attrs %{
    name: "Acme Corp",
    key: "acme-corp",
    languages: ["en", "no"],
    default_language: "en",
    status: :active,
    delivery_mode: :static,
    deploy_config: %{strategy: :rsync, target: "web@example:/srv/acme"}
  }

  test "the registry schema is permanently public" do
    assert Site.__schema__(:prefix) == "public"
  end

  test "accepts a complete site registry record" do
    assert changeset = Site.changeset(@valid_attrs)
    assert changeset.valid?

    site = Ecto.Changeset.apply_changes(changeset)
    assert site.key == "acme-corp"
    assert site.delivery_mode == :static
    assert site.deploy_config.strategy == :rsync
  end

  test "rejects unsafe keys" do
    changeset = Site.changeset(%{@valid_attrs | key: "Acme Corp"})

    refute changeset.valid?
    assert changeset.errors[:key]
  end

  test "requires the default language to be configured for the site" do
    changeset = Site.changeset(%{@valid_attrs | default_language: "de"})

    refute changeset.valid?
    assert {"must be included in languages", _} = changeset.errors[:default_language]
  end

  test "rejects empty, duplicate, and malformed language sets" do
    for languages <- [[], ["en", "en"], ["EN"]] do
      changeset = Site.changeset(%{@valid_attrs | languages: languages})
      refute changeset.valid?
      assert changeset.errors[:languages]
    end
  end

  test "validates static deployment targets and optional notification URLs" do
    missing_target = Site.changeset(%{@valid_attrs | deploy_config: %{strategy: :s3}})
    refute missing_target.valid?

    invalid_webhook =
      Site.changeset(%{
        @valid_attrs
        | deploy_config: %{
            strategy: :s3,
            target: "s3://acme-site",
            webhook_url: "javascript:alert(1)"
          }
      })

    refute invalid_webhook.valid?

    assert Site.changeset(%{
             @valid_attrs
             | deploy_config: %{
                 strategy: :s3,
                 target: "s3://acme-site/static",
                 webhook_url: "https://hooks.example.test/published",
                 retention_count: 25
               }
           }).valid?
  end
end
