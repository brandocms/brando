defmodule Brando.Repo.Migrations.FixGalleryRefsInModules do
  use Ecto.Migration
  import Ecto.Query

  def change do
    # Fix gallery refs in modules to use the new |gallery filter pattern
    # After brando_136, the pattern should be refs.ref_name.gallery.gallery_objects
    
    # Get all modules that might contain gallery refs  
    modules_with_gallery_refs = 
      from(m in "content_modules", 
           where: like(m.code, "%refs.%.gallery.gallery_objects%"),
           select: %{id: m.id, code: m.code})
      |> Brando.repo().all()

    Enum.each(modules_with_gallery_refs, fn module ->
      updated_code = fix_gallery_refs(module.code)
        
      if updated_code != module.code do
        from(m in "content_modules", where: m.id == ^module.id)
        |> Brando.repo().update_all(set: [code: updated_code])
        
        IO.puts("Updated module ID #{module.id}")
      end
    end)
  end

  defp fix_gallery_refs(code) do
    code
    # Find and fix gallery loops to use the new filter pattern
    |> fix_gallery_loops_with_filter()
  end

  defp fix_gallery_loops_with_filter(code) do
    # Find all for loops that iterate over refs.*.gallery.gallery_objects and capture the loop variable
    pattern = ~r/(\s*){%\s*for\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+in\s+refs\.([a-zA-Z_][a-zA-Z0-9_]*)\.gallery\.gallery_objects\s*%}/
    
    # Replace the for loops with assign + new for loop
    updated_code = 
      String.replace(code, pattern, fn match ->
        # Extract the captured groups from the match
        [_, indent, loop_var, ref_name] = Regex.run(pattern, match)
        """
#{indent}{% comment %} Original loop var: #{loop_var} {% endcomment %}
#{indent}{% assign gallery_objects = refs.#{ref_name}|gallery %}
#{indent}{% for gallery_object in gallery_objects %}
"""
      end)
    
    # Now fix the contents based on the comment markers
    fix_gallery_loop_contents_with_markers(updated_code)
  end

  defp fix_gallery_loop_contents_with_markers(code) do
    # Split into lines for processing
    lines = String.split(code, "\n")
    
    {updated_lines, _} = 
      Enum.map_reduce(lines, %{in_gallery_loop: false, old_var: nil}, fn line, state ->
        cond do
          # Found our comment marker with the original variable name
          match = Regex.run(~r/{%\s*comment\s*%}\s*Original loop var:\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*{%\s*endcomment\s*%}/, line) ->
            [_, old_var] = match
            new_state = %{state | old_var: old_var}
            {"", new_state}  # Remove the comment line
          
          # Start of gallery loop
          String.match?(line, ~r/for\s+gallery_object\s+in\s+gallery_objects/) ->
            new_state = %{state | in_gallery_loop: true}
            {line, new_state}
          
          # End of loop (endfor)
          String.match?(line, ~r/\s*{%\s*endfor\s*%}/) and state.in_gallery_loop ->
            new_state = %{state | in_gallery_loop: false, old_var: nil}
            {line, new_state}
          
          # Inside gallery loop - replace old variable with gallery_object.image
          state.in_gallery_loop and state.old_var ->
            old_var = state.old_var
            updated_line = 
              line
              # Replace old_var.attribute with gallery_object.image.attribute
              |> String.replace(~r/\b#{Regex.escape(old_var)}\.([a-zA-Z_][a-zA-Z0-9_]*)/, "gallery_object.image.\\1")
              # Replace {{ old_var }} with {{ gallery_object.image }}
              |> String.replace(~r/{{\s*#{Regex.escape(old_var)}\s*}}/, "{{ gallery_object.image }}")
              # Replace {% if old_var %} with {% if gallery_object.image %}
              |> String.replace(~r/{\%\s*if\s+#{Regex.escape(old_var)}\s*\%}/, "{% if gallery_object.image %}")
              # Replace other standalone uses of old_var
              |> String.replace(~r/\b#{Regex.escape(old_var)}\b(?![\.\w])/, "gallery_object.image")
            
            {updated_line, state}
          
          true ->
            {line, state}
        end
      end)
    
    updated_lines
    |> Enum.reject(&(&1 == ""))  # Remove empty lines from removed comments
    |> Enum.join("\n")
  end
end