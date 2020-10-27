export default {
  "en": {
    "<%= vue_plural %>": {
      "title": "<%= Recase.SentenceCase.convert(plural) %>",
      "subtitle": "Administration",
      "index": "Index",
      "new": "New entry",
      "edit": "Edit entry",
      "delete": "Delete entry",
      "actions": "Actions",
      "sequence-updated": "Sequence updated",
      "created": "Entry created",
      "edited": "Entry updated",
      "deleted": "Entry deleted",
      "delete-entries": "Delete entries",
      "delete-confirm": "Are you sure you want to delete this?",
      "delete-confirm-many": "Are you sure you want to delete these entries?",
      "help-text": "",
      "more": "More",
      "fields": {
        <%= for { lf, idx } <- Enum.with_index(vue_locales["en"]) do %>"<%= Recase.to_camel(lf.field) %>": {
          "label": "<%= lf.label %>",
          "placeholder": "<%= lf.placeholder %>",
          "helpText": "<%= lf.help_text %>"
        }<%= if idx < Enum.count(vue_locales["en"]) - 1 do %>,<% end %>
        <% end %>
      }
    }
  },
  "no": {
    "<%= vue_plural %>": {
      "title": "<%= Recase.SentenceCase.convert(plural) %>",
      "subtitle": "Administrasjon",
      "index": "Oversikt",
      "new": "Nytt objekt",
      "edit": "Rediger objekt",
      "delete": "Slett objekt",
      "actions": "Handlinger",
      "created": "Objekt opprettet",
      "deleted": "Objektet ble slettet",
      "edited": "Objektet ble oppdatert",
      "delete-entries": "Slett objekter",
      "delete-confirm": "Er du sikker på at du vil slette dette?",
      "delete-confirm-many": "Er du sikker på at du vil slette disse?",
      "sequence-updated": "Rekkefølge oppdatert",
      "help-text": "",
      "more": "Mer",
      "fields": {
        <%= for {lf, idx} <- Enum.with_index(vue_locales["no"]) do %>"<%= Recase.to_camel(lf.field) %>": {
          "label": "<%= lf.label %>",
          "placeholder": "<%= lf.placeholder %>",
          "helpText": "<%= lf.help_text %>"
        }<%= if idx < Enum.count(vue_locales["no"]) - 1 do %>,<% end %>
        <% end %>
      }
    }
  }
}
