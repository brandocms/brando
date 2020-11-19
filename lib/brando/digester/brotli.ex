defmodule Brando.Digester.Brotli do
  @behaviour Phoenix.Digester.Compressor
  def compress_file(file_path, content) do
    valid_extension = Path.extname(file_path) in Application.fetch_env!(:phoenix, :gzippable_exts)
    compressed_content = :brotli.encode(content)

    if valid_extension && byte_size(compressed_content) < byte_size(content) do
      {:ok, compressed_content}
    else
      :error
    end
  end

  def file_extensions do
    [".br"]
  end
end
