defmodule Brando.Trait.Meta do
  @moduledoc false
  use Brando.Trait

  @meta_fields [:meta_title, :meta_description]

  def generate_code(_, _) do
    quote do
      attributes do
        attribute :meta_title, :text
        attribute :meta_description, :text
      end

      assets do
        asset :meta_image, :image,
          cfg: %{
            formats: [:jpg],
            allowed_mimetypes: ["image/jpeg", "image/png"],
            default_size: "xlarge",
            upload_path: Path.join(["images", "meta"]),
            random_filename: true,
            size_limit: 5_240_000,
            sizes: %{
              "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
              "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
              "xlarge" => %{"size" => "1200x630", "quality" => 75, "crop" => true}
            }
          }
      end
    end
  end

  def ai_field_opts(_module, _config, field_name) when field_name not in @meta_fields, do: []

  def ai_field_opts(_module, config, field_name) do
    config
    |> Map.get(:ai, %{})
    |> get_value(field_name)
    |> normalize_ai_opts()
  end

  defp get_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, Atom.to_string(key))
  end

  defp get_value(config, key) when is_list(config) do
    Keyword.get(config, key)
  end

  defp get_value(_, _), do: nil

  defp normalize_ai_opts(nil), do: []
  defp normalize_ai_opts(opts) when is_list(opts), do: opts
  defp normalize_ai_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_ai_opts(_), do: []
end
