---
name: wenmar
description: Read and change data in a Wenmar Pro auto-repair shop (work orders, customers, vehicles, parts, labor, packages) through the `wenmar` command-line client. Use when the user asks about the shop's work orders, estimates, customers, vehicles, parts, labor, or packages, or wants to create or update any of them.
---

# Wenmar Pro

`wenmar` is the command-line client for Wenmar Pro, a shop-management system for
auto-repair shops. Every command calls the shop's Wenmar Pro server with **your
agent token**. A `write` token can do the shop work the user who connected you
can do; a `read` token can only read. No agent token can add, change, disable
or re-PIN users, or create or revoke agent tokens: a person does that. Every
write is recorded in the shop's audit log as this agent.

## Profile and sign-in

A person connected you by running `wenmar setup claude` (or `setup codex`,
`setup hermes`, `setup agent`). That saved a profile, normally named `agent`,
holding your
token. Always run commands with that profile:

```sh
wenmar -P agent status
WENMAR_PROFILE=agent wenmar wo list
wenmar -P agent doctor
```

- Never sign in yourself and never ask for a PIN.
- If a command exits `2`, stop and ask the person to run `wenmar setup claude`
  again (their token was revoked or the user was disabled).
- `wenmar -P agent doctor` shows your agent name, your scope (`read` or
  `write`), and the user you act for.
- The person may have limited what you can do. `wenmar doctor` shows your
  scope; a `403 not_authorized` or a `confirmation_required` answer means
  this action is switched off for you: tell the person, do not retry and do
  not look for another way.

## Output

Piped output (how you run commands) is bare JSON data on stdout. Pick at most
one mode flag per command:

| Flag | Output |
|---|---|
| none (piped) | bare JSON data |
| `--json` | envelope `{"ok", "data", "summary", "breadcrumbs", "meta"}`; `breadcrumbs` are suggested next commands |
| `--jq EXPR` | built-in jq filter applied to the data |
| `--ids-only` | only the `id` values |
| `--count` | the total number of records |
| `--markdown` | Markdown tables; `wo show --markdown` is a readable work-order document |

```sh
wenmar -P agent wo list --json
wenmar -P agent wo list --jq '.[] | .id'
wenmar -P agent customers list --ids-only
wenmar -P agent wo list --count
wenmar -P agent wo show 42 --markdown
```

Errors go to **stderr** as JSON:
`{"ok": false, "error": {"code", "message", "hint", "details"}}`. Read `hint`;
it usually names the fix command.

| Exit | Meaning | What to do |
|---|---|---|
| 0 | ok | |
| 1 | usage or generic error | fix the command; check `wenmar <command> --help --agent` |
| 2 | not signed in / token rejected | ask the person to run `wenmar setup claude` |
| 3 | not found | check the id |
| 4 | validation | fix the fields named in `error.details` |
| 5 | rate limited | wait, then retry (reads only) |
| 6 | server error | report it; never retry a write |
| 7 | conflict | re-read the record, then decide |
| 8 | forbidden | `agent_read_only`: your token is read-only. `agent_forbidden`: no agent may do this (users, PINs, agent tokens, the in-app assistant); a person must. Otherwise the user you act for lacks that permission. Tell the person. |
| 9 | partial read refused | add `--allow-partial` or narrow the query |
| 10 | network | run `wenmar -P agent doctor` |

## Commands by noun

`wenmar commands --json` prints the whole catalog: every command, argument,
and flag, with `"write": true` on commands that change data.
`wenmar <command> --help --agent` prints one command as JSON. Use it before
any create or update to see the exact flags.

### Work orders (`wo`)

```sh
wenmar -P agent wo list
wenmar -P agent wo show 42
wenmar -P agent wo show 42 --markdown
wenmar -P agent wo create --help --agent
wenmar -P agent wo update --help --agent
wenmar -P agent wo start 42
wenmar -P agent wo complete 42
wenmar -P agent wo reopen 42
wenmar -P agent wo services --help --agent
wenmar -P agent wo line-items --help --agent
wenmar -P agent wo apply-package --help --agent
```

`wo close`, `wo void`, and `wo decline` change money or end the job: ask the
person first.

### Customers and vehicles

```sh
wenmar -P agent customers list
wenmar -P agent customers show 7
wenmar -P agent customers create --help --agent
wenmar -P agent vehicles list
wenmar -P agent vehicles show 3
wenmar -P agent search "brake pads"
```

### Parts, labor, packages

```sh
wenmar -P agent parts list
wenmar -P agent labor list
wenmar -P agent packages list
wenmar -P agent packages show 5
```

### The shop

```sh
wenmar -P agent users list
wenmar -P agent locations list
wenmar -P agent jobs list
```

`jobs list` works only when the user you act for is an owner.

### `query` — the shop's data

`query` answers business questions from the analytics database: the saved and built-in
reports, and SQL. It only runs `SELECT`s — nothing changes. "Business questions" below
says when to use it.

```sh
wenmar query suggest
wenmar query list
wenmar query run revenue_by_category --range last_month
wenmar query sql "SELECT COUNT(*) AS work_orders FROM work_orders"
wenmar query schema
wenmar query save zz_report --question "How many work orders are there?" --sql "SELECT COUNT(*) AS work_orders FROM work_orders"
wenmar query remove zz_report
wenmar query refresh
wenmar query export revenue_by_category --format csv
```

`--sql -` reads the SQL from stdin. `query save` is a write: tell the person what you
saved. `query refresh` is limited to one refresh per 15 minutes. `query export` refuses
to overwrite an existing file without `--force`. Money prints as dollars (`27,960.00`),
and every answer says how many rows it has and when the data is from.

## Business questions

For sales, revenue, customers, parts and what is owed, use `wenmar query`, not the list
commands.

- `wenmar query suggest` — the reports this shop can run. Offer two or three by their
  question.
- `wenmar query run revenue_by_category --range last_month`
- `wenmar query schema`, then `wenmar query sql "SELECT …"` only when no report fits.
- `wenmar query save <name> --question "…" --sql "…"` after a new query answered the
  question and the user wants to keep it.
- `wenmar query export <name> --format csv` when the user wants a file.

Every answer says when the data was last refreshed (each evening). For a question about
today, run `wenmar query refresh` first. Money is printed in dollars. Do not show SQL or
table names unless the user asks.

## How the shop is doing

For "how are we doing", "what should we improve" and "did things get better", use
`wenmar review`.

- `wenmar review findings` — what is worth the owner's attention, with the figures. Give at
  most three.
- `wenmar review list` — the reviews that were taken.
- `wenmar review compare baseline month_2` — a later review beside an earlier one, against
  the same weeks last year and against the trend.
- `wenmar review compare baseline month_2 --publish` — the same with no dollar figures, for
  showing outside the shop.
- `wenmar review create month_2 --weeks 8` — store a new review. Ask for the name and the
  period first. A stored review never changes.
- `wenmar review measures` — what each measure means.
- `wenmar review observe estimate_minutes 14.5` — record a number measured by hand.
- `wenmar review log-change "Hired a technician" --kind people` — record something that
  changed at the shop.
- `wenmar review notes` — the hand measures and the change log.

A measure that compares "in part" changed partly because records are kept better now: say
so. "After only" means there is no figure from before the move to Wenmar. A dash is nothing
to measure, never zero.

## Pagination

Lists return one page (the server's default size) unless you ask for more.
The server allows at most 100 per page. `--all` follows the server's next-page
links (up to 50 pages). If `--all` or `--limit` stops before the server's
total, the command refuses with exit 9 unless you pass `--allow-partial`.
Pagination notices go to stderr, so stdout stays valid JSON.

```sh
wenmar -P agent wo list --page 2 --per-page 50
wenmar -P agent customers list --limit 200
wenmar -P agent wo list --all
wenmar -P agent wo list --all --allow-partial
```

## Writing safely

- Read before you write: `show` the record and confirm the id.
- **Never retry a write automatically.** After exit 6 or 10 on a write, re-read
  the record to see whether the write happened before doing anything else.
- Creates accept `--idempotency-key KEY`. Use a new unique key for each create
  you intend. Reuse the same key only to repeat that same create after an
  uncertain failure; the server then returns the first result instead of
  creating a duplicate.
- Payments, invoices, closing, and voiding move money. Ask the person before
  any of them.
- Free-text flags accept `-` to read the text from stdin.

```sh
wenmar -P agent customers create --first-name Grace --last-name Hopper --idempotency-key 3f2a9c1e-grace-hopper
```

## Anything without a command: `tools`

Every server operation is reachable by name, even before it has its own
command. `tools list` prints each tool's name, description, and JSON schema
for its params. Record tools take `{"id": …}`, `{"attrs": {…}}`, or
`{"filters": {…}}`.

```sh
wenmar -P agent tools list
wenmar -P agent tools call customers.show --params '{"id": 7}'
wenmar -P agent tools call customers.list --params '{"filters": {}}'
wenmar -P agent tools call customers.create --params @customer.json
wenmar -P agent tools call customers.create --params -
```

Creates accept `--idempotency-key KEY`: use a new key per create; reuse the
same key to retry that same create after an uncertain failure (the server
returns the first result). Without the flag no key is sent, and a write is
never retried.

## Discovery

```sh
wenmar commands --json
wenmar wo list --help --agent
wenmar --help --agent
wenmar help exit-codes
wenmar skill
```

## MCP (`wenmar mcp`)

`wenmar mcp` is an MCP server on stdio for agents that prefer tools to shell
commands. It is a proxy for the server's own MCP endpoint, with the same agent
profile, token and permissions as the CLI: a `read` agent can only read, and
every write is audited as the agent.

Register it once (`wenmar setup claude|codex|hermes` prints the line with
your agent profile):

```
claude mcp add wenmar -- wenmar -P claude mcp
codex mcp add wenmar -- wenmar -P codex mcp
```

`wenmar doctor` checks the registration.

- The tools are the server's catalog: the pinned workflow tools, plus
  `tools_search` (find a tool by what it does), `tools_read` (run a tool that only
  reads) and `tools_call` (run it).
  `wenmar_identity` says which profile and server this connection uses.
- A list returns `{data, total, next_offset}`; pass `limit` (max 100) and
  `offset` for more.
- Money is in cents and quantities in hundredths.
- Errors are tool results with `isError: true` and
  `{error: {code, message, hint, details, field_errors}}` in
  `structuredContent`; fix the params and call again. A tool that answers
  `confirmation_required` cannot be run from here — use the CLI with the
  person.
- Writes are never retried for you. To retry a create safely, re-run it
  through the CLI with `tools call <name> --idempotency-key <key>`.
