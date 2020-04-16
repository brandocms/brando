defmodule Brando.Generators.Vue do
  @locales ["en", "nb"]

  def before_copy(binding) do
    binding
    |> add_vue_locales()
    |> add_vue_inputs()
    |> add_vue_form_queries()
    |> add_vue_defaults()
    |> add_vue_contentlist_rows()
  end

  def after_copy(binding) do
    add_to_files(binding)
  end

  defp add_to_files(binding) do
    ## MENUS

    Mix.Brando.add_to_file(
      "assets/backend/src/menus/index.js",
      "imports",
      "import #{binding[:vue_plural]} from './#{binding[:vue_plural]}'"
    )

    Mix.Brando.add_to_file(
      "assets/backend/src/menus/index.js",
      "content",
      "#{binding[:vue_plural]}"
    )

    ## ROUTES

    Mix.Brando.add_to_file(
      "assets/backend/src/routes/index.js",
      "imports",
      "import #{binding[:vue_plural]} from './#{binding[:vue_plural]}'"
    )

    Mix.Brando.add_to_file(
      "assets/backend/src/routes/index.js",
      "content",
      "#{binding[:vue_plural]}",
      prepend: true,
      comma: true
    )

    filename =
      "assets/backend/src/views/#{binding[:snake_domain]}/#{
        Recase.to_pascal(binding[:vue_singular])
      }Form.vue"

    Enum.map(binding[:assocs], fn {_, {:references, target}} ->
      Mix.Brando.add_to_file(
        filename,
        "imports",
        "import GET_#{String.upcase(Atom.to_string(target))} from '../../gql/#{
          binding[:snake_domain]
        }/#{String.upcase(binding[:plural])}_QUERY.graphql'"
      )
    end)

    binding
  end

  defp add_vue_contentlist_rows(binding) do
    attrs = Keyword.get(binding, :attrs)
    vue_singular = Keyword.get(binding, :vue_singular)
    vue_plural = Keyword.get(binding, :vue_plural)

    vue_contentlist_rows =
      Enum.map(attrs, fn
        {k, {:array, _}} ->
          {k, ""}

        {k, :boolean} ->
          {k, ~s(<div class="col-2">
            <CheckOrX :val="entry.#{k}" />
          </div>)}

        {k, :date} ->
          {k, ~s(<div class="col-2">
            {{ entry.#{k} | datetime }}
          </div>)}

        {k, :time} ->
          {k, ~s(<div class="col-2">
            {{ entry.#{k} | datetime }}
          </div>)}

        {k, :datetime} ->
          {k, ~s(<div class="col-2">
            {{ entry.#{k} | datetime }}
          </div>)}

        {k, :image} ->
          {k, ~s(<div class="col-2">
            <img
              v-if="entry.#{k}"
              :src="entry.#{k}.thumb"
              class="avatar-sm img-border-lg" />
          </div>)}

        {k, :villain} ->
          {k, ""}

        {k, :status} ->
          {k, ""}

        {k, :gallery} ->
          {k, ""}

        {:title = k, _} ->
          {k, ~s(<div class="col-2">
            <router-link
              :to="{ name: '#{vue_plural}-edit', params: { #{vue_singular}Id: entry.id } }"
              class="entry-link">
              {{ entry.#{k} }}
            </router-link>
          </div>)}

        {:name = k, _} ->
          {k, ~s(<div class="col-2">
            <router-link
              :to="{ name: '#{vue_plural}-edit', params: { #{vue_singular}Id: entry.id } }"
              class="entry-link">
              {{ entry.#{k} }}
            </router-link>
          </div>)}

        {:heading = k, _} ->
          {k, ~s(<div class="col-2">
            <router-link
              :to="{ name: '#{vue_plural}-edit', params: { #{vue_singular}Id: entry.id } }"
              class="entry-link">
              {{ entry.#{k} }}
            </router-link>
          </div>)}

        {k, _} ->
          {k, ~s(<div class="col-2">
            {{ entry.#{k} }}
          </div>)}
      end)

    Keyword.put(binding, :vue_contentlist_rows, vue_contentlist_rows)
  end

  defp add_vue_defaults(binding) do
    attrs = Keyword.get(binding, :attrs)

    vue_defaults =
      Enum.map(attrs, fn
        {k, {:array, _}} ->
          {k, nil, nil}

        {k, :boolean} ->
          {k, "false"}

        {k, :text} ->
          {k, "''"}

        {k, :string} ->
          {k, "''"}

        {k, :villain} ->
          k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")
          {k, "null"}

        {k, _} ->
          {k, "null"}
      end)

    Keyword.put(binding, :vue_defaults, vue_defaults)
  end

  defp add_vue_locales(binding) do
    all_fields = Keyword.get(binding, :assocs) ++ Keyword.get(binding, :attrs)

    # this is for locale.js
    vue_locales =
      Enum.map(@locales, fn locale ->
        fields =
          Enum.map(all_fields, fn
            {k, {_, _}} ->
              string_key = to_string(k) <> "_id"

              %{
                field: string_key,
                label: String.capitalize(Atom.to_string(k)),
                placeholder: String.capitalize(Atom.to_string(k)),
                help_text: ""
              }

            {k, _} ->
              string_key = to_string(k)

              %{
                field: string_key,
                label: String.capitalize(string_key),
                placeholder: String.capitalize(string_key),
                help_text: ""
              }
          end)

        {locale, fields}
      end)
      |> Enum.into(%{})

    Keyword.put(binding, :vue_locales, vue_locales)
  end

  defp add_vue_form_queries(binding) do
    assocs = Keyword.get(binding, :assocs)

    if Enum.count(assocs) > 0 do
      queries =
        Enum.reduce(assocs, "", fn {_field, {:references, target}}, acc ->
          acc <>
            """
              #{target}: {
                  query: GET_#{String.upcase(Atom.to_string(target))}
                },
            """
        end)

      vue_form_queries = """
      apollo: {
        #{queries}
        },
      """

      Keyword.put(binding, :vue_form_queries, vue_form_queries)
    else
      Keyword.put(binding, :vue_form_queries, "")
    end
  end

  defp add_vue_inputs(binding) do
    # this is for vue components
    attrs = Keyword.get(binding, :attrs)
    assocs = Keyword.get(binding, :assocs)

    vue_assoc_inputs =
      Enum.map(assocs, fn
        {k, {:references, ref_target}} ->
          k = String.to_atom(Atom.to_string(k) <> "_id")
          binding = binding ++ [k: k, ref_target: ref_target]

          filename =
            Application.app_dir(
              :brando,
              "priv/templates/brando.gen/assets/backend/vue_inputs/references.eex"
            )

          {k, EEx.eval_file(filename, binding)}
      end)

    vue_inputs =
      Enum.map(attrs, fn
        {k, {:array, _}} ->
          {k, nil, nil}

        {k, :gallery} ->
          {k, nil, nil}

        {k, {:slug, target}} ->
          binding = binding ++ [k: k, target: target]

          filename =
            Application.app_dir(
              :brando,
              "priv/templates/brando.gen/assets/backend/vue_inputs/slug.eex"
            )

          {k, EEx.eval_file(filename, binding)}

        {k, type} ->
          k =
            cond do
              type == :villain and k == :data ->
                :data

              type == :villain ->
                String.to_atom(Atom.to_string(k) <> "_data")

              true ->
                k
            end

          binding = binding ++ [k: k]

          filename =
            Application.app_dir(
              :brando,
              "priv/templates/brando.gen/assets/backend/vue_inputs/#{type}.eex"
            )

          {k, EEx.eval_file(filename, binding)}
      end)

    Keyword.put(binding, :vue_inputs, vue_assoc_inputs ++ vue_inputs)
  end
end
