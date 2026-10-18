---
name: wenmar
description: Read and change a Wenmar Pro auto-repair shop's work orders, estimates, customers, vehicles, parts and reports with the wenmar CLI.
metadata: {"openclaw": {"requires": {"bins": ["wenmar"]}}, "hermes": {"tags": ["auto-repair", "shop-management", "work-orders"], "category": "business"}}
---

# Wenmar Pro

`wenmar` is the command-line client for Wenmar Pro, a shop-management system for
auto-repair shops. Every command calls the shop's Wenmar Pro server with **your
agent token**. A `write` token can do the shop work the user who connected you
can do; a `read` token can only read. No agent token can add, change, disable
or re-PIN users, or create or revoke agent tokens: a person does that. Every
write is recorded in the shop's audit log as this agent.

## Profile and sign-in

A person connected you by running `wenmar setup hermes` (or `setup openclaw`,
`setup claude`, `setup codex`, `setup agent`). That saved a profile named
`agent` holding your token. Always run commands with that profile:

```sh
wenmar -P agent status
WENMAR_PROFILE=agent wenmar wo list
wenmar -P agent doctor
```

- Never sign in yourself and never ask for a PIN.
- `wenmar -P agent doctor` shows your agent name, your scope (`read` or
  `write`), and the user you act for.

## Start of a conversation

```sh
wenmar -P agent prime
wenmar -P agent today
```

Run `prime` first: the rules, then the shop's date, who you act for, and the open orders (`today` is only the live part). If live data is missing, say the fix it names.

## Talking to the shop

You usually work for an owner, a service advisor or a technician who is in the
shop and reads you on a phone, in a chat app.

- Answer in plain words and short lines. Give money in dollars.
- Name a work order by its number and its customer and vehicle, not by a
  database id alone.
- Do not show JSON, SQL, table names or commands unless the person asks.
- After a change, say in one line what you changed.
- When a command fails, say what went wrong in the shop's words and what the
  person can do about it.

## Five rules

1. Read before you write: `show` the record and confirm it is the one the
   person means.
2. **Never retry a write automatically.** After exit 6 or 10 on a write,
   re-read the record to see whether the write happened.
3. Give each create a new `--idempotency-key`. Reuse a key only to repeat that
   same create after an uncertain failure.
4. Payments, invoices, `wo close`, `wo void` and `wo decline` move money or end
   the job: say what you will do and wait for the person's yes.
5. Exit 8, `403 not_authorized` or `confirmation_required` means this action is
   switched off for you: tell the person; do not retry and do not look for
   another way. Exit 2: stop and ask the person to run `wenmar setup` for this
   agent again.

## Output and exit codes

Piped output is bare JSON data on stdout. Errors are JSON on stderr:
`{"ok": false, "error": {"code", "message", "hint", "details"}}`. Read `hint`;
it usually names the fix.

| Exit | Meaning |
|---|---|
| 0 | ok |
| 1 | usage or generic error |
| 2 | not signed in / token rejected |
| 3 | not found |
| 4 | validation: fix the fields in `error.details` |
| 5 | rate limited: wait, then retry (reads only) |
| 6 | server error |
| 7 | conflict: re-read, then decide |
| 8 | forbidden |
| 9 | partial read refused: add `--allow-partial` or narrow the query |
| 10 | network: run `wenmar -P agent doctor` |

## Most-used commands

```sh
wenmar -P agent search "brake pads"
wenmar -P agent wo list
wenmar -P agent wo show 42
wenmar -P agent wo show 42 --markdown
wenmar -P agent wo create --help --agent
wenmar -P agent wo start 42
wenmar -P agent wo complete 42
wenmar -P agent customers show 7
wenmar -P agent vehicles show 3
wenmar -P agent parts list
wenmar -P agent query suggest
wenmar -P agent review findings
```

`wenmar <command> --help --agent` prints one command's flags as JSON; use it
before any create or update. Free-text flags accept `-` to read the text from
stdin.

## References

Read a reference when the task needs it. Each is a file next to this one and
is also printed by `wenmar skill <name>`:

- `references/work-orders.md`: work orders, customers, vehicles, parts,
  labor, packages, users and locations; paging through long lists; writing
  safely.
- `references/business-questions.md`: sales, revenue, what is owed, "how are
  we doing" (`query` and `review`).
- `references/output-and-errors.md`: every output flag, the full exit-code
  table with what to do, and how to discover commands.
- `references/tools-and-mcp.md`: server operations that have no command yet
  (`tools`), and the MCP server.

```sh
wenmar skill work-orders
wenmar skill business-questions
wenmar skill output-and-errors
wenmar skill tools-and-mcp
```
