defmodule Brando.Migrations.FixAssignedGalleryLoopsTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @migration Application.app_dir(
               :brando,
               "priv/templates/brando.upgrade/migrations/brando_200_fix_assigned_gallery_loops.exs"
             )

  # Modules 20, 21 and 23 from smartwatt, as brando_136 left them.
  @fixtures Path.expand("../../fixtures/gallery_loops", __DIR__)
  @modules ~w(integration_compatibility info_slider logo_marquee)
  @tenant "tenant_acme_staging"

  setup_all do
    [{module, _bytecode}] = Code.compile_file(@migration)
    on_exit(fn -> :code.delete(module) and :code.purge(module) end)
    %{migration: module}
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name <> ".liquid"))

  describe "rewrite/1" do
    for name <- @modules do
      test "fixes the #{name} module", %{migration: migration} do
        assert migration.rewrite(fixture(unquote(name))) == fixture(unquote(name) <> ".fixed")
      end

      test "leaves the fixed #{name} module alone", %{migration: migration} do
        fixed = fixture(unquote(name) <> ".fixed")
        assert migration.rewrite(fixed) == fixed
      end
    end

    test "rewrites every read of the loop variable in Liquid, not in HTML or strings", %{migration: migration} do
      code = """
      {%- assign images = refs.slider.gallery.gallery_objects -%}
      <p>{{ images | size }} images</p>
      {% for image in images limit: 3 %}
        <div class="image" data-label="image">
          {% if image.alt %}{{ image.alt }}{% endif %}
          {% picture image { srcset: 'image', alt: "image" } %}
          {% for format in image.formats %}{{ format }}{% endfor %}
        </div>
      {% endfor %}
      {% for image in other_images %}{% picture image %}{% endfor %}
      """

      assert migration.rewrite(code) == """
             {%- assign images = refs.slider.gallery.gallery_objects -%}
             <p>{{ images | size }} images</p>
             {% for image in images limit: 3 %}
               <div class="image" data-label="image">
                 {% if image.image.alt %}{{ image.image.alt }}{% endif %}
                 {% picture image.image { srcset: 'image', alt: "image" } %}
                 {% for format in image.image.formats %}{{ format }}{% endfor %}
               </div>
             {% endfor %}
             {% for image in other_images %}{% picture image %}{% endfor %}
             """
    end

    test "fixes loops over the gallery filter and directly over the ref", %{migration: migration} do
      code = """
      {% assign objects = refs.photos | gallery %}{% for photo in objects %}{{ photo.path }}{% endfor %}
      {% for photo in refs.photos.gallery.gallery_objects %}{{ photo.path }}{% endfor %}
      """

      assert migration.rewrite(code) == """
             {% assign objects = refs.photos | gallery %}{% for photo in objects %}{{ photo.image.path }}{% endfor %}
             {% for photo in refs.photos.gallery.gallery_objects %}{{ photo.image.path }}{% endfor %}
             """
    end

    test "fixes a direct loop with nested loops and HTML that names the variable", %{migration: migration} do
      code = """
      {% for image in refs.slider.gallery.gallery_objects %}
        <figure class="image">
          {% for tag in image.tags %}{{ tag }}{% endfor %}
          {% picture image { srcset: 'default' } %}
        </figure>
      {% endfor %}
      """

      assert migration.rewrite(code) == """
             {% for image in refs.slider.gallery.gallery_objects %}
               <figure class="image">
                 {% for tag in image.image.tags %}{{ tag }}{% endfor %}
                 {% picture image.image { srcset: 'default' } %}
               </figure>
             {% endfor %}
             """
    end

    test "leaves loops brando_141 already converted alone", %{migration: migration} do
      code = """
      {% assign gallery_objects = refs.photos|gallery %}
      {% for gallery_object in gallery_objects %}
        {% picture gallery_object.image %}
        {% if gallery_object.video %}{{ gallery_object.video.url }}{% endif %}
      {% endfor %}
      """

      assert migration.rewrite(code) == code
    end
  end

  test "rewrites stored module code in public and every environment", %{migration: migration} do
    Brando.MigrationTemplates.create_environment(@tenant, ["content_modules"])

    ids =
      for schema <- ["public", @tenant], name <- @modules, into: %{} do
        %{rows: [[id]]} =
          Repo.query!(
            """
            INSERT INTO "#{schema}".content_modules (uid, class, code, inserted_at, updated_at)
            VALUES ($1, $2, $3, NOW(), NOW()) RETURNING id
            """,
            [Brando.Utils.generate_uid(), name, fixture(name)]
          )

        {{schema, name}, id}
      end

    for _run <- 1..2 do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

      for {{schema, name}, id} <- ids do
        %{rows: [[code]]} = Repo.query!(~s(SELECT code FROM "#{schema}".content_modules WHERE id = $1), [id])
        assert code == fixture(name <> ".fixed")
      end
    end
  end
end
