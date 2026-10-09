defmodule BrandoAdmin.Components.Form.AltTextSuggestionTest do
  # The form describes an image in a `start_async` task, which starts
  # without the LiveView's process context. `describe_task/2` carries it, so
  # an image in a named environment (a tenant prefix) is found there.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Images.Image
  alias Brando.Tenant
  alias BrandoAdmin.Components.Form.AltTextSuggestion

  @prefix "tenant_alt-suggestion_preview"
  @fixture Path.expand("../../../fixtures/sample.jpg", __DIR__)

  setup do
    Brando.AIStub.configure()
    Brando.AIStub.reply(~s({"en": "Two ferries", "no": "To ferjer"}))
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    on_exit(fn -> Tenant.put_prefix(nil) end)

    Ecto.Adapters.SQL.query!(BrandoIntegration.Repo, ~s|CREATE SCHEMA "#{@prefix}"|)

    Ecto.Adapters.SQL.query!(
      BrandoIntegration.Repo,
      ~s|CREATE TABLE "#{@prefix}"."images" (LIKE public."images" INCLUDING ALL)|
    )

    Tenant.put_prefix(@prefix)
    sizes = Map.new(~w(thumb small medium large xlarge), &{&1, "images/alt-env/#{&1}.jpg"})

    image =
      Brando.Repo.insert!(%Image{
        path: "images/alt-env/a.jpg",
        status: :processed,
        width: 600,
        height: 400,
        sizes: sizes,
        config_target: "default",
        alt: nil
      })

    target = Path.join(Brando.Tenant.Storage.current_media_root(), Brando.Images.AltText.rendition(image))
    File.mkdir_p!(Path.dirname(target))
    File.cp!(@fixture, target)

    %{image: image}
  end

  test "describes an image in the caller's environment", %{image: image} do
    describe = AltTextSuggestion.describe_task(image.id)

    assert {:ok, %{values: %{"en" => "Two ferries", "no" => "To ferjer"}}} =
             fn -> describe.() end |> Task.async() |> Task.await()
  end

  test "a task without the context looks in the wrong environment", %{image: image} do
    assert {:error, {:image, :not_found}} =
             fn -> Brando.Images.AltText.describe(image.id) end |> Task.async() |> Task.await()
  end
end
