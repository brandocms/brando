- An entry's language versions are one set, the same from every version: a translation's content language switch opens a version linked to its source instead of saying "No access", an entry linked to one with a German version offers it instead of a second German one, and the Languages drawer lists the versions linked through another one.

- `Brando.Translations.language_versions/3` returns the whole set: `linked` holds `%{entry, linked?, via}` maps, and `unlinked` is now `matched`, those in the trash included.
