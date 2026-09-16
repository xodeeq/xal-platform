# `docs/spec/` — what this service must be

The **spec** is the document that says what this service is for, what it owns, what it does
not own, and what "done" means for it. It is the input to planning, not a summary of the
code.

A spec is not authored here. It is **admitted** to
`xal-company/specs/admitted/<service>/<version>.md` with typed frontmatter and ten numbered
sections, verbatim, and the admission ledger holds a `sha256` per file that the intake gate
recomputes on every run — so an edit after admission is a red build in that repo. That is
what makes "admitted verbatim" checkable rather than promised.

So this directory holds **`service.md`, a pointer**: the service, the spec version, the
ledger digest, and a link. Cite the spec by the identity it carries — `service` plus
`spec_version` — never by a filename in prose.

Copying the spec body here would create a second copy that nothing diffs, in the one place a
reader would most reasonably trust. Don't.
