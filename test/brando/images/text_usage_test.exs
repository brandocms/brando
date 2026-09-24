defmodule Brando.Images.TextUsageTest do
  use ExUnit.Case, async: true

  alias Brando.Images.TextUsage

  test "reads a Blueprint's image asset names" do
    source = """
    assets do
      asset :cover, :image, cfg: [upload_path: "images/cover"]
      asset :listing_image, :image
      asset :brochure, :file
      asset(:hero, :image)
    end
    """

    assert TextUsage.image_assets(source) == ["cover", "listing_image", "hero"]
  end

  test "finds code reading an image's texts, by asset and common image names" do
    code = """
    <img alt={@entry.listing_image.alt} />
    {image.title}
    {img.credits}
    {@entry.title}
    {my_image.alt}
    {Brando.Images.text(image, :alt, @language)}
    """

    assert TextUsage.scan_code(code, ["listing_image"]) == [
             %{line: 1, text: "<img alt={@entry.listing_image.alt} />"},
             %{line: 2, text: "{image.title}"},
             %{line: 3, text: "{img.credits}"}
           ]
  end

  test "finds Liquid output tags that print an image's texts without i18n" do
    liquid = """
    <figure>
      {% picture entry.cover %}
      <figcaption>{{ entry.cover.title }}</figcaption>
      <p>{{ entry.cover.credits | i18n }}</p>
      {% if entry.cover.alt %}<p>{{- image.alt -}}</p>{% endif %}
      <h1>{{ entry.title }}</h1>
    </figure>
    """

    assert TextUsage.scan_liquid(liquid) == [
             %{line: 3, text: "{{ entry.cover.title }}"},
             %{line: 5, text: "{{- image.alt -}}"}
           ]
  end
end
