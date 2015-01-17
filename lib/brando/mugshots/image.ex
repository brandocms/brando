defmodule Brando.Mugshots.Model.Image do
  @cfg [
    allowed_exts: [
      "jpg", "jpeg", "png"
    ],
    default_size: :medium,
    upload_path: Path.join("images", "default"),
    size_limit: 10240000,
    sizes: [
      thumb: [
        size: "150x150",
        quality: 100,
        crop: true
      ],
      small: [
        size: "300x",
        quality: 100
      ],
      medium: [
        size: "500x",
        quality: 100
      ],
      large: [
        size: "700x",
        quality: 100
      ],
      xlarge: [
        size: "900x",
        quality: 100
      ]
    ]
  ]

  def config(key) do
    @cfg[key]
  end

  def config do
    @cfg
  end

  def get_sizes do
    Keyword.keys(config[:sizes])
  end

  def get_size(size) do
    config[:sizes][size]
  end
end