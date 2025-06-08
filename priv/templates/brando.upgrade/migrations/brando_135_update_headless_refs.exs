defmodule Brando.Migrations.UpdateHeadlessRefs do
  use Ecto.Migration
  import Ecto.Query
  alias Brando.Repo

  def up do
    # This migration needs to be done programmatically to check ref types
    # We'll process each module and update its code based on the actual ref types
    
    modules = Repo.all(
      from m in "content_modules",
      select: %{id: m.id, code: m.code},
      where: fragment("? ~ ?", m.code, "refs\\.[a-zA-Z0-9_]+\\.data\\.")
    )
    
    Enum.each(modules, fn module ->
      updated_code = update_module_code(module.id, module.code)
      
      if updated_code != module.code do
        Repo.update_all(
          from(m in "content_modules", where: m.id == ^module.id),
          set: [code: updated_code]
        )
      end
    end)
    
    # Same for templates
    templates = Repo.all(
      from t in "content_templates",
      select: %{id: t.id, code: t.code},
      where: fragment("? ~ ?", t.code, "refs\\.[a-zA-Z0-9_]+\\.data\\.")
    )
    
    Enum.each(templates, fn template ->
      updated_code = update_template_code(template.id, template.code)
      
      if updated_code != template.code do
        Repo.update_all(
          from(t in "content_templates", where: t.id == ^template.id),
          set: [code: updated_code]
        )
      end
    end)
  end
  
  defp update_module_code(module_id, code) do
    # Get all refs for modules that use this module
    refs = get_refs_for_module(module_id)
    
    # Build a map of ref names to their types
    ref_types = Enum.reduce(refs, %{}, fn ref, acc ->
      ref_type = get_ref_type(ref)
      Map.put(acc, ref.name, ref_type)
    end)
    
    # Now update the code based on ref types
    code
    |> update_picture_refs(ref_types)
    |> update_video_refs(ref_types)
    |> update_gallery_refs(ref_types)
  end
  
  defp update_template_code(template_id, code) do
    # For templates, we need to find which modules use this template
    # and get their refs
    modules_using_template = Repo.all(
      from m in "content_modules",
      where: m.template_id == ^template_id,
      select: m.id
    )
    
    # Get all refs from these modules
    all_refs = Enum.flat_map(modules_using_template, &get_refs_for_module/1)
    
    # Build ref types map
    ref_types = Enum.reduce(all_refs, %{}, fn ref, acc ->
      ref_type = get_ref_type(ref)
      Map.put(acc, ref.name, ref_type)
    end)
    
    # Update the code
    code
    |> update_picture_refs(ref_types)
    |> update_video_refs(ref_types)
    |> update_gallery_refs(ref_types)
  end
  
  defp get_refs_for_module(module_id) do
    Repo.all(
      from r in "content_refs",
      where: r.module_id == ^module_id,
      select: %{name: r.name, data: r.data}
    )
  end
  
  defp get_ref_type(%{data: data}) when is_map(data) do
    Map.get(data, "type")
  end
  defp get_ref_type(_), do: nil
  
  defp update_picture_refs(code, ref_types) do
    # Find all ref names that are pictures
    picture_refs = ref_types
      |> Enum.filter(fn {_name, type} -> type == "picture" end)
      |> Enum.map(fn {name, _type} -> name end)
    
    Enum.reduce(picture_refs, code, fn ref_name, acc ->
      # Replace refs.<ref_name>.data.data.<property> with refs.<ref_name>.<property>
      String.replace(acc, ~r/refs\.#{ref_name}\.data\.data\.(\w+)/, "refs.#{ref_name}.\\1")
    end)
  end
  
  defp update_video_refs(code, ref_types) do
    # Find all ref names that are videos
    video_refs = ref_types
      |> Enum.filter(fn {_name, type} -> type == "video" end)
      |> Enum.map(fn {name, _type} -> name end)
    
    Enum.reduce(video_refs, code, fn ref_name, acc ->
      # Replace refs.<ref_name>.data.data.<property> with refs.<ref_name>.<property>
      String.replace(acc, ~r/refs\.#{ref_name}\.data\.data\.(\w+)/, "refs.#{ref_name}.\\1")
    end)
  end
  
  defp update_gallery_refs(code, ref_types) do
    # Find all ref names that are galleries
    gallery_refs = ref_types
      |> Enum.filter(fn {_name, type} -> type == "gallery" end)
      |> Enum.map(fn {name, _type} -> name end)
    
    Enum.reduce(gallery_refs, code, fn ref_name, acc ->
      acc
      # Replace refs.<ref_name>.data.images with refs.<ref_name>.gallery.gallery_objects
      |> String.replace(~r/refs\.#{ref_name}\.data\.images/, "refs.#{ref_name}.gallery.gallery_objects")
      # Also handle any other data.data patterns for galleries
      |> String.replace(~r/refs\.#{ref_name}\.data\.data\.(\w+)/, "refs.#{ref_name}.\\1")
    end)
  end
  
  def down do
    # Since we're flattening the structure based on type, the down migration
    # would need to restore the nested structure, which is complex
    # For now, we'll leave this as a one-way migration
    IO.puts "Warning: This migration cannot be fully reversed. The nested ref structure cannot be automatically restored."
  end
end