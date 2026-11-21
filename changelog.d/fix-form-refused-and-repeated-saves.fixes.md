- A save that keeps another editor's value in a field while a subform row is refused shows the row's error instead of crashing the form.

- A revision stored after correcting the subform row it was refused for is stored, instead of refused again until another field changed.

- A save without block fields that stays on the form collects the transformer rows again on the next save, so that save writes the rows as they are then instead of the first save's.
