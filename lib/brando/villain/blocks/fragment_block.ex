defmodule Brando.Villain.Blocks.FragmentBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "FragmentBlockData",
      singular: "fragment_block_data",
      plural: "fragment_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    relations do
      relation :fragment, :belongs_to, module: Brando.Pages.Fragment
    end
  end

  use Brando.Villain.Block,
    type: "fragment"

  def protected_attrs do
    [:fragment_id]
  end
end
