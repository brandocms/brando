defmodule Brando.Generators.Schema do
  import Inflex

  def before_copy(binding) do
    binding
    |> add_schema_fields
    |> add_schema_assocs
    |> add_optional_fields
    |> add_required_fields
  end

  def after_copy(binding) do
    binding
  end

  defp add_optional_fields(binding) do
    binding_map = Enum.into(binding, %{})

    fields = []

    {_, fields} =
      {binding_map, fields}
      |> maybe_add_gallery_fields()
      |> maybe_add_img_fields()
      |> maybe_add_video_fields()
      |> maybe_add_file_fields()
      |> maybe_add_soft_delete()

    optional_fields = "~w(#{Enum.join(fields, " ")})a"
    Keyword.put(binding, :optional_fields, optional_fields)
  end

  defp add_required_fields(binding) do
    binding_map = Enum.into(binding, %{})

    fields =
      binding[:attrs]
      |> Keyword.drop(Keyword.values(binding[:img_fields]))
      |> Keyword.drop(Keyword.values(binding[:video_fields]))
      |> Keyword.drop(Keyword.values(binding[:file_fields]))
      |> Keyword.drop(Keyword.values(binding[:villain_fields]))
      |> Keyword.drop(Keyword.values(binding[:gallery_fields]))
      |> Enum.map_join(" ", &elem(&1, 0))
      |> maybe_add_creator_field(binding_map)
      |> maybe_add_villain_fields(binding_map)
      |> maybe_add_schema_assocs(binding_map)

    required_fields = "~w(#{fields})a"
    Keyword.put(binding, :required_fields, required_fields)
  end

  defp maybe_add_creator_field(fields, %{creator: false}), do: fields

  defp maybe_add_creator_field(fields, %{creator: true}),
    do: Enum.join([fields, "creator_id"], " ")

  defp maybe_add_villain_fields(fields, %{villain_fields: []}), do: fields

  defp maybe_add_villain_fields(fields, %{villain_fields: villain_fields}) do
    extra_fields =
      Enum.map_join(villain_fields, " ", fn {_k, v} ->
        if v == :data, do: "#{v}", else: "#{v}_data"
      end)

    Enum.join([fields, extra_fields], " ")
  end

  defp maybe_add_schema_assocs(fields, %{schema_assocs: []}), do: fields

  defp maybe_add_schema_assocs(fields, %{
         schema_assocs: schema_assocs,
         gallery_fields: gallery_fields
       }) do
    extra_fields =
      Enum.map_join(schema_assocs, " ", fn {_, y, _} ->
        if to_string(y) in Keyword.values(gallery_fields), do: nil, else: y
      end)

    Enum.join([fields, extra_fields], " ")
  end

  defp add_schema_fields(binding) do
    attrs = Keyword.get(binding, :attrs)
    types = Keyword.get(binding, :types)
    defaults = Keyword.get(binding, :defaults)

    schema_fields =
      Enum.map(attrs, fn {k, v} ->
        case v do
          :villain -> (k == :data && "villain()") || "villain #{inspect(k)}"
          :gallery -> (k == :image_series && "gallery()") || "gallery #{inspect(k)}"
          {:slug, _} -> "field #{inspect(k)}, :string"
          _ -> "field #{inspect(k)}, #{inspect(types[k])}#{defaults[k]}"
        end
      end)

    Keyword.put(binding, :schema_fields, schema_fields)
  end

  defp add_schema_assocs(binding) do
    assocs = Keyword.get(binding, :assocs)
    domain = Keyword.get(binding, :domain)
    base = Keyword.get(binding, :base)

    schema_assocs =
      Enum.reduce(assocs, [], fn
        {key, {:references, :users}}, acc ->
          [{key, :"#{key}_id", "Brando.Users.User"} | acc]

        {key, {:references, target}}, acc ->
          inflected = singularize(to_string(target)) |> camelize()
          [{key, :"#{key}_id", Enum.join([base, domain, inflected], ".")} | acc]
      end)

    Keyword.put(binding, :schema_assocs, schema_assocs)
  end

  defp maybe_add_gallery_fields({%{gallery_fields: []} = binding, fields}), do: {binding, fields}

  defp maybe_add_gallery_fields({%{gallery_fields: gallery_fields} = binding, fields}) do
    gallery_fields = Enum.map(gallery_fields, fn {_, v} -> "#{v}_id" end)
    {binding, fields ++ gallery_fields}
  end

  defp maybe_add_img_fields({%{img_fields: []} = binding, fields}), do: {binding, fields}

  defp maybe_add_img_fields({%{img_fields: img_fields} = binding, fields}) do
    img_fields = Enum.map(img_fields, &elem(&1, 1))
    {binding, fields ++ img_fields}
  end

  defp maybe_add_video_fields({%{video_fields: []} = binding, fields}), do: {binding, fields}

  defp maybe_add_video_fields({%{video_fields: video_fields} = binding, fields}) do
    video_fields = Enum.map(video_fields, &elem(&1, 1))
    {binding, fields ++ video_fields}
  end

  defp maybe_add_file_fields({%{file_fields: []} = binding, fields}), do: {binding, fields}

  defp maybe_add_file_fields({%{file_fields: file_fields} = binding, fields}) do
    file_fields = Enum.map(file_fields, &elem(&1, 1))
    {binding, fields ++ file_fields}
  end

  defp maybe_add_soft_delete({%{soft_delete: false} = binding, fields}), do: {binding, fields}

  defp maybe_add_soft_delete({%{soft_delete: true} = binding, fields}) do
    {binding, fields ++ ["deleted_at"]}
  end
end
