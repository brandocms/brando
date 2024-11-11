defmodule Brando.Repo.Migrations.I18nModules do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table(:content_modules) do
      add :i18n_name, :jsonb
      add :i18n_namespace, :jsonb
      add :i18n_help_text, :jsonb
    end

    flush()

    # lets migrate them to english, since that will be our fallback for these strings
    modules = from(m in "content_modules", select: %{id: m.id, name: m.name, namespace: m.namespace, help_text: m.help_text}) |> Brando.Repo.all()
    admin_languages =
      :admin_languages
      |> Brando.config()
      |> Enum.map(fn [{:value, val}, {:text, _text}] -> val end)

    for module <- modules do
      {i18n_name, i18n_namespace, i18n_help_text} = Enum.reduce(admin_languages, {%{}, %{}, %{}}, fn lang, acc ->
        {name_map, namespace_map, help_text_map} = acc

        if lang == "en" do
          {Map.put(name_map, "en", module.name), Map.put(namespace_map, "en", module.namespace), Map.put(help_text_map, "en", module.help_text)}
        else
          {Map.put(name_map, lang, nil), Map.put(namespace_map, lang, nil), Map.put(help_text_map, lang, nil)}
        end
      end)

      i18n_namespace =
        if module.namespace == "general" do
          nil
        else
          i18n_namespace
        end

      from(m in "content_modules", where: m.id == ^module.id)
      |> Brando.Repo.update_all(set: [
        i18n_name: i18n_name,
        i18n_namespace: module.namespace == "general" && nil || i18n_namespace,
        i18n_help_text: i18n_help_text
        ])
    end

    alter table(:content_modules) do
      remove :name
      remove :namespace
      remove :help_text
    end

    rename table(:content_modules), :i18n_name, to: :name
    rename table(:content_modules), :i18n_namespace, to: :namespace
    rename table(:content_modules), :i18n_help_text, to: :help_text
  end

  def down do
    # reverse the migration
    alter table(:content_modules) do
      add :temp_name, :text
      add :temp_namespace, :text
      add :temp_help_text, :text
    end

    flush()

    # Migrate data back from jsonb to text columns
    modules = from(m in "content_modules", select: %{id: m.id, name: m.name, namespace: m.namespace, help_text: m.help_text}) |> Brando.Repo.all()

    for module <- modules do
      temp_name = get_in(module.name, ["en"]) || ""
      temp_namespace = get_in(module.namespace, ["en"]) || ""
      temp_help_text = get_in(module.help_text, ["en"]) || ""

      from(m in "content_modules", where: m.id == ^module.id)
      |> Brando.Repo.update_all(set: [
        temp_name: temp_name,
        temp_namespace: temp_namespace,
        temp_help_text: temp_help_text
      ])
    end

    alter table(:content_modules) do
      remove :name
      remove :namespace
      remove :help_text
    end

    rename table(:content_modules), :temp_name, to: :name
    rename table(:content_modules), :temp_namespace, to: :namespace
    rename table(:content_modules), :temp_help_text, to: :help_text
  end
end
