defmodule Brando.Content.ModuleSetModule do
  @moduledoc """
  Blueprint for the ModuleSetModule schema — a join table between ModuleSet and Module.
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "ModuleSetModule",
    singular: "module_set_module",
    plural: "module_set_modules",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  alias Brando.Content

  @type t :: %__MODULE__{}

  @allow_mark_as_deleted true

  # ++ Traits
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Sequenced
  # --

  relations do
    relation :module, :belongs_to, module: Content.Module
    relation :module_set, :belongs_to, module: Content.ModuleSet
  end

  absolute_url ""

  translations do
    context :naming do
      translate :singular, t("module set")
      translate :plural, t("module sets")
    end
  end

  factory %{}
end
