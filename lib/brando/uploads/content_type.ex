defmodule Brando.Uploads.ContentType do
  @moduledoc """
  What an uploaded file really holds, read from its first bytes.

  A browser's `type` comes from the file's extension, and a crafted client can
  send anything, so what is stored and what reaches a parser is judged here. A
  raster image under another raster format's name keeps working, as libvips
  reads it by its contents; it only has to be a format the field allows. SVG is
  stricter, because it takes a different path through storage and through a
  browser: the name, the declared type and the contents have to agree.

  Files can hold anything. A direct file or video never reaches the server, so
  those are judged by the bucket's size and type alone.
  """
  use Gettext, backend: Brando.Gettext

  alias Brando.Images.SvgRoot

  @svg "image/svg+xml"
  @isobmff_video ~w(video/mp4 video/quicktime video/x-m4v)
  @avif_brands ~w(avif avis)
  @heic_brands ~w(heic heix hevc mif1 msf1)

  @doc "The first bytes of a file, as many as the checks here look at."
  @spec head(Path.t()) :: {:ok, binary} | {:error, term}
  def head(path) do
    with {:ok, io} <- File.open(path, [:read, :binary]) do
      data = IO.binread(io, SvgRoot.scan_bytes())
      File.close(io)
      if is_binary(data), do: {:ok, data}, else: {:ok, ""}
    end
  end

  @doc "The image type `data` holds, or `nil` for anything else."
  @spec image(binary) :: String.t() | nil
  def image(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  def image(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: "image/png"
  def image(<<"GIF8", _::binary>>), do: "image/gif"
  def image(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: "image/webp"

  def image(<<_size::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>) when brand in @avif_brands,
    do: "image/avif"

  def image(<<_size::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>) when brand in @heic_brands,
    do: "image/heic"

  def image(<<"II*", 0, _::binary>>), do: "image/tiff"
  def image(<<"MM", 0, "*", _::binary>>), do: "image/tiff"
  def image(<<"BM", _::binary>>), do: "image/bmp"

  def image(data) do
    case SvgRoot.parse(data) do
      {:error, :not_svg} -> nil
      _svg -> @svg
    end
  end

  @doc """
  `:ok` when `data`, the start of a file, is an image the allowed types take,
  and agrees with its name and declared type about being an SVG. Otherwise
  `{:error, message}`, safe to show.
  """
  @spec verify_image(binary, String.t(), String.t(), [String.t()]) :: :ok | {:error, String.t()}
  def verify_image(data, name, declared_type, allowed) do
    actual = image(data)

    with :ok <- verify_svg(data, actual, name, declared_type) do
      verify_allowed_image(actual, allowed)
    end
  end

  @doc """
  `:ok` when `data`, the start of a file, is a video container the allowed
  types take. Otherwise `{:error, message}`, safe to show.
  """
  @spec verify_video(binary, [String.t()]) :: :ok | {:error, String.t()}
  def verify_video(data, allowed) do
    case video(data) do
      [] ->
        {:error, mismatch_message()}

      [actual | _] = types ->
        if allowed == ["*"] or Enum.any?(types, &(&1 in allowed)),
          do: :ok,
          else: {:error, rejected_message(actual, allowed)}
    end
  end

  defp verify_svg(data, actual, name, declared_type) do
    claims = [actual == @svg, declared_type == @svg, name |> Path.extname() |> String.downcase() == ".svg"]

    cond do
      not Enum.any?(claims) ->
        :ok

      not Enum.all?(claims) ->
        {:error, mismatch_message()}

      SvgRoot.parse(data) == {:error, :entities} ->
        {:error, gettext("This SVG declares entities, which are not allowed.")}

      true ->
        :ok
    end
  end

  defp verify_allowed_image(_actual, ["*"]), do: :ok
  defp verify_allowed_image(nil, _allowed), do: {:error, mismatch_message()}

  defp verify_allowed_image(actual, allowed) do
    if allowed_image?(actual, allowed), do: :ok, else: {:error, rejected_message(actual, allowed)}
  end

  # An AVIF or HEIC is the same container as an MP4, told apart by its brand
  defp video(<<_size::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>)
       when brand in @avif_brands or brand in @heic_brands,
       do: []

  defp video(<<_size::binary-size(4), box::binary-size(4), _::binary>>)
       when box in ~w(ftyp styp uuid moov mdat free skip wide pnot),
       do: @isobmff_video

  defp video(<<0x1A, 0x45, 0xDF, 0xA3, _::binary>>), do: ~w(video/webm video/x-matroska)
  defp video(<<"RIFF", _size::binary-size(4), "AVI ", _::binary>>), do: ~w(video/x-msvideo video/avi)
  defp video(<<"OggS", _::binary>>), do: ~w(video/ogg application/ogg)
  defp video(_data), do: []

  defp allowed_image?("image/jpeg", allowed), do: "image/jpeg" in allowed or "image/jpg" in allowed
  defp allowed_image?(actual, allowed), do: actual in allowed

  defp mismatch_message, do: gettext("The file's contents do not match its type.")

  defp rejected_message(actual, allowed) do
    gettext("Rejected type [%{rejected}]. Allowed: %{allowed}", %{rejected: actual, allowed: inspect(allowed)})
  end
end
