export default {
  "en": {
    "<%= vue_plural %>": {
      "edit": "Edit entry",
      "delete": "Delete entry",
      "title": "<%= Recase.SentenceCase.convert(plural) %>",
      "subtitle": "Administration",
      "index": "Index",
      "actions": "Actions",
      "new": "New entry",
      "sequence_updated": "Sequence updated",
      "deleted": "Entry deleted",
      "delete-entries": "Delete entries",
      "delete-confirm": "Are you sure you want to delete this?",
      "delete-confirm-many": "Are you sure you want to delete these entries?",
      "sequence-updated": "Sequence updated",
      "help-text": "",
      "more": "More",
      "fields": {
        <%= for {lf, idx} <- Enum.with_index(vue_locales["en"]) do %>"<%= lf.field %>": {
          "label": "<%= lf.label %>",
          "placeholder": "<%= lf.placeholder %>",
          "help_text": "<%= lf.help_text %>"
        }<%= if idx < Enum.count(vue_locales["en"]) - 1 do %>,<% end %>
        <% end %>
      }
    }
  },
  "nb": {
    "<%= vue_plural %>": {
      "edit": "Rediger objekt",
      "delete": "Slett objekt",
      "title": "<%= Recase.SentenceCase.convert(plural) %>",
      "subtitle": "Administrasjon",
      "index": "Oversikt",
      "actions": "Handlinger",
      "new": "Nytt objekt",
      "sequence_updated": "Rekkefølgen ble oppdatert",
      "deleted": "Objektet ble slettet",
      "delete-entries": "Slett objekter",
      "delete-confirm": "Er du sikker på at du vil slette dette?",
      "delete-confirm-many": "Er du sikker på at du vil slette disse?",
      "sequence-updated": "Rekkefølge oppdatert",
      "help-text": "",
      "more": "Mer",
      "fields": {
        <%= for {lf, idx} <- Enum.with_index(vue_locales["nb"]) do %>"<%= lf.field %>": {
          "label": "<%= lf.label %>",
          "placeholder": "<%= lf.placeholder %>",
          "help_text": "<%= lf.help_text %>"
        }<%= if idx < Enum.count(vue_locales["nb"]) - 1 do %>,<% end %>
        <% end %>
      }
    }
  }
}
