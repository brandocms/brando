- A content-transfer import no longer brings back a block of a module in the trash: a module put in the trash after the preview refuses the import, naming the entry, the block and the module, and a preview that maps a module in the trash names it to whoever may read modules.

- Recovering a content-transfer import that would put back a block of a module in the trash is refused, naming the module, and can be retried once the module is restored.

- A content-transfer import or recovery that runs while a definition apply changes a module it uses waits for the apply, instead of deadlocking with it.
