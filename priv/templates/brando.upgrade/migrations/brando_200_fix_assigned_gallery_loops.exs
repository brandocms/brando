defmodule Brando.Repo.Migrations.Brando200FixAssignedGalleryLoops do
  use Ecto.Migration

  @moduledoc """
  `brando_136` rewrote a gallery ref's legacy `data.data.images` to
  `refs.<ref>.gallery.gallery_objects`, so a loop over it now yields
  `GalleryObject`s instead of images. This repairs loops written directly over
  the ref (which `brando_141` used to handle, unreliably):

      {% for image in refs.slider.gallery.gallery_objects %}

  and loops over a variable assigned from it, which nothing repaired:

      {% assign images = refs.slider.gallery.gallery_objects %}
      {% for image in images %}
        {% picture image { srcset: 'default' } %}
        {{ image.alt }}
      {% endfor %}

  This rewrites the loop variable inside such loops to `image.image`. The
  assigned variable is left alone, so `{{ images | size }}` keeps working.

  A loop whose body already reads `<var>.image` or `<var>.video` is taken to
  be correct and left alone, which also makes the migration safe to run again.
  Only Liquid output and tags are rewritten; HTML text and quoted strings in
  the loop body are not.

  Module code is the only stored template that can reference `refs`.
  """

  # `refs.<ref>.gallery.gallery_objects` or `refs.<ref> | gallery`
  @gallery_source ~S"refs\.\w+(?:\.gallery\.gallery_objects|\s*\|\s*gallery)"
  @tag ~r/\{%-?\s*(\w+)(.*?)-?%\}/s
  @liquid ~r/\{\{.*?\}\}|\{%.*?%\}/s
  @quoted ~r/('[^']*'|"[^"]*")/

  def up do
    for prefix <- prefixes(), {id, code} <- modules(prefix) do
      case rewrite(code) do
        ^code -> :ok
        fixed -> repo().query!(~s(UPDATE "#{prefix}".content_modules SET code = $1 WHERE id = $2), [fixed, id])
      end
    end
  end

  def down, do: :ok

  @doc false
  def rewrite(code) do
    gallery_vars =
      for [_, var] <- Regex.scan(~r/\{%-?\s*assign\s+(\w+)\s*=\s*#{@gallery_source}\s*-?%\}/, code),
          into: MapSet.new(),
          do: var

    rewrite_loops(code, gallery_vars, 0)
  end

  # Rewrites the `nth` for loop and moves on. Loops are found again after
  # every rewrite, because rewriting a body shifts the offsets after it.
  defp rewrite_loops(code, gallery_vars, nth) do
    tags = Regex.scan(@tag, code, return: :index)

    case tags |> Enum.with_index() |> Enum.filter(&for_tag?(code, &1)) |> Enum.at(nth) do
      nil ->
        code

      {[{tag_start, tag_length} | _] = tag, index} ->
        with var when is_binary(var) <- gallery_loop_var(code, tag, gallery_vars),
             {body_start, body_end} <- body(code, tags, index, tag_start + tag_length),
             body = binary_part(code, body_start, body_end - body_start),
             false <- reads_object?(body, var) do
          fixed = Regex.replace(@liquid, body, &object_to_image(&1, var))

          code = binary_part(code, 0, body_start) <> fixed <> binary_part(code, body_end, byte_size(code) - body_end)
          rewrite_loops(code, gallery_vars, nth + 1)
        else
          _ -> rewrite_loops(code, gallery_vars, nth + 1)
        end
    end
  end

  defp for_tag?(code, {[_, name | _], _}), do: part(code, name) == "for"

  defp gallery_loop_var(code, [_, _, args], gallery_vars) do
    case Regex.run(~r/^\s*(\w+)\s+in\s+(#{@gallery_source}|\w+)(?=\s|$)/, part(code, args)) do
      [_, var, "refs." <> _] -> var
      [_, var, source] -> if MapSet.member?(gallery_vars, source), do: var
      nil -> nil
    end
  end

  # The body runs from the end of the `for` tag to its matching `endfor`.
  defp body(code, tags, index, body_start) do
    tags
    |> Enum.drop(index + 1)
    |> Enum.reduce_while(1, fn [{start, _}, name | _], depth ->
      case part(code, name) do
        "for" -> {:cont, depth + 1}
        "endfor" when depth == 1 -> {:halt, {body_start, start}}
        "endfor" -> {:cont, depth - 1}
        _ -> {:cont, depth}
      end
    end)
    |> case do
      {_, _} = body -> body
      _unclosed -> nil
    end
  end

  defp reads_object?(body, var) do
    @liquid
    |> Regex.scan(body)
    |> Enum.any?(fn [liquid] -> Regex.match?(~r/(?<![\w.])#{var}\.(?:image|video)\b/, liquid) end)
  end

  # `image` → `image.image` in a `{{ }}` or `{% %}`, outside quoted strings.
  defp object_to_image(liquid, var) do
    @quoted
    |> Regex.split(liquid, include_captures: true)
    |> Enum.map_join(fn
      "'" <> _ = quoted -> quoted
      "\"" <> _ = quoted -> quoted
      unquoted -> Regex.replace(~r/(?<![\w.])#{var}(?!\w)/, unquoted, "#{var}.image")
    end)
  end

  defp part(code, {start, length}), do: binary_part(code, start, length)

  defp modules(prefix) do
    %{rows: rows} =
      repo().query!(
        ~s(SELECT id, code FROM "#{prefix}".content_modules WHERE code LIKE '%refs.%' AND code LIKE '%gallery%')
      )

    Enum.map(rows, fn [id, code] -> {id, code} end)
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
