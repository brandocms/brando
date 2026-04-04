defmodule Brando.Repo.Migrations.FixLegacyContentData do
  use Ecto.Migration
  import Ecto.Query

  @moduledoc """
  Fixes content data issues that can occur during migration from older Brando versions.

  1. Fixes double-encoded jsonb strings in content_refs
  2. Converts markdown content in text refs to HTML
  3. Fixes modules that iterate refs (must use {% ref refs.name %})
  4. Sets tiptap extensions on Legacy Content Wrapper refs
  5. Backfills nil focal points on images
  """

  def up do
    fix_double_encoded_refs()
    convert_markdown_refs_to_html()
    fix_ref_iterating_modules()
    set_legacy_wrapper_extensions()
    # Fix any double-encoding caused by previous steps
    fix_double_encoded_refs()
    # Delete orphaned list-type module template refs (modules now use table_rows)
    delete_orphaned_list_refs()
    backfill_image_focal_points()
  end

  def down do
    :ok
  end

  # -- Fix double-encoded jsonb strings in content_refs --

  defp fix_double_encoded_refs do
    Brando.repo().query!("""
      UPDATE content_refs
      SET data = (data #>> '{}')::jsonb
      WHERE jsonb_typeof(data) = 'string'
    """)
  end

  # -- Convert markdown content in text refs to HTML --

  defp convert_markdown_refs_to_html do
    text_refs =
      Brando.repo().all(
        from(r in "content_refs",
          select: %{id: r.id, data: r.data},
          where: fragment("data->>'type' = 'text'")
        )
      )

    for ref <- text_refs do
      text = get_in(ref.data, ["data", "text"])

      if text && is_binary(text) && is_markdown?(text) do
        case Earmark.as_html(text) do
          {:ok, html, _} ->
            updated_data = put_in(ref.data, ["data", "text"], html)
            update_ref_data(ref.id, updated_data)

          _ ->
            :skip
        end
      end
    end
  end

  defp is_markdown?(text) do
    Regex.match?(~r/^\#{1,6}\s/m, text) or
      Regex.match?(~r/\[.*?\]\(.*?\)/, text) or
      Regex.match?(~r/^\*\*.*\*\*/m, text)
  end

  # -- Fix modules that iterate refs with {% for ref in refs %} --

  defp fix_ref_iterating_modules do
    Brando.repo().query!("""
      UPDATE content_modules
      SET code = '{% ref refs.content %}'
      WHERE code LIKE '%for ref in refs%'
        AND (SELECT count(*) FROM content_refs WHERE module_id = content_modules.id) = 1
        AND EXISTS (SELECT 1 FROM content_refs WHERE module_id = content_modules.id AND name = 'content')
    """)
  end

  # -- Set tiptap extensions on Legacy Content Wrapper text refs --

  defp set_legacy_wrapper_extensions do
    extensions = ["p", "h4", "list", "link", "bold", "italic"]

    %{rows: rows} =
      Brando.repo().query!("""
        SELECT id FROM content_modules
        WHERE name::text LIKE '%Legacy Content Wrapper%'
        LIMIT 1
      """)

    case rows do
      [[module_id]] ->
        refs =
          Brando.repo().all(
            from(r in "content_refs",
              join: b in "content_blocks",
              on: r.block_id == b.id,
              where: b.module_id == ^module_id,
              select: %{id: r.id, data: r.data}
            )
          )

        for ref <- refs, is_map(ref.data) do
          updated = put_in(ref.data, ["data", "extensions"], extensions)
          update_ref_data(ref.id, updated)
        end

        template_refs =
          Brando.repo().all(
            from(r in "content_refs",
              where: r.module_id == ^module_id,
              select: %{id: r.id, data: r.data}
            )
          )

        for ref <- template_refs, is_map(ref.data) do
          updated = put_in(ref.data, ["data", "extensions"], extensions)
          update_ref_data(ref.id, updated)
        end

      _ ->
        :ok
    end
  end

  # -- Delete orphaned list-type template refs --

  defp delete_orphaned_list_refs do
    Brando.repo().query!("""
      DELETE FROM content_refs
      WHERE data->>'type' = 'list'
    """)
  end

  # -- Backfill nil focal points on images --

  defp backfill_image_focal_points do
    Brando.repo().query!("""
      UPDATE images SET focal = '{"x": 50, "y": 50}'::jsonb WHERE focal IS NULL
    """)
  end

  # -- Helper: update ref data without double-encoding --

  defp update_ref_data(ref_id, data) do
    from(r in "content_refs", where: r.id == ^ref_id)
    |> Brando.repo().update_all(set: [data: data])
  end
end
