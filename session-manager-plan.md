# LLMBox Service — Plan

## Goal

Replace the current `claudebox` shell-script flow with a small persistent
service that manages Claude Code containers on the dev box, so that:

1. Closing VSCode (or the terminal, or losing SSH) does **not** kill a
   running Claude session — you can reconnect to it later.
2. New Claude sessions can be started on the dev box from a normal
   conversation on claude.ai (desktop or phone), without needing the dev
   machine's UI open at all.

This is explicitly a stepping stone toward a future Kubernetes + CephFS
architecture where Claude instances run in the cluster. That bigger system
is out of scope here; the value of this project is that it solves the
"can't start a session from my phone" problem today and produces something
useful even if the cluster version never ships.

## Interaction model

Two entry points, one backend.

**Local entry point (VSCode task / terminal).**
The existing `claudebox` task continues to work. Running it shows a single
list-style screen of conversations resumable for the current project,
sorted by last activity, with a marker for each session's state (connected
to a terminal / detached but container running / no container). A pinned
"new session" entry sits at the top. A filter hotkey narrows by state.
Pressing Enter does the smart thing: attach if detached, take over if
connected, start a fresh container resuming that conversation if there is
no container.

**Remote entry point (claude.ai).**
The service exposes an MCP server registered against the user's Claude
account. From any claude.ai conversation — desktop or phone — the user
can ask Claude to list available projects, start a new session in one,
list running sessions, or stop one. The newly started Claude instance
runs with `--remote-control`, so it appears in the user's Claude
ecosystem and is immediately usable from claude.ai for actual work.

## Core design choices

**Container as session host, not session.**
Each Claude session runs inside its own container, but Claude itself runs
inside a detachable terminal multiplexer (e.g. `dtach`) inside that
container. The terminal that the user sees is just an attach client.
Closing the terminal detaches; it does not stop the container. This is
the load-bearing decision — it's what makes "close VSCode without losing
the session" possible.

**One daemon, two listeners.**
A single user-level daemon process owns all state (known projects,
running containers, session-to-container mapping). It exposes:

- A local Unix socket for the `claudebox` CLI.
- An HTTP/SSE listener for the MCP server.

These are two listeners on the same in-memory state, not two services
that have to stay in sync.

**State is recoverable from Docker.**
Containers are tagged with labels identifying their project and session.
If the daemon crashes or restarts, it rebuilds its view of the world by
listing labeled containers. There is no separate state file that can
drift out of sync with reality.

## What the daemon does

- Discovers candidate projects by scanning
  `~/source/*/.llmbox/docker-compose.yml`. The container's `working_dir`
  from compose is the canonical project key.
- Tracks running containers by Docker label.
- Knows, for each project, which `~/.claude/projects/` directory holds
  the resumable conversations for it (the directory derived from the
  container's `working_dir`, not the host path).
- Knows, for each project, the set of host checkouts that map to its
  `working_dir` (often one, sometimes several — e.g. `DesignAssistant`
  and `DesignAssistant-2` both mapping to `/work/DesignAssistant`).
- Knows, for each conversation, whether there is a container running for
  it, whether that container currently has an attached terminal, and
  which host checkout that container is bind-mounted from.
- Starts containers on request (from local CLI or MCP), passing the
  resume flag if the request names a specific past conversation, and
  selecting a host checkout per the rules in the "Checkouts vs
  `working_dir`" section.
- Stops containers on request.
- Mediates take-overs (force-detach an existing client and let the new
  one in) when requested.

## What the local CLI does

- Resolves the current directory to a project (the existing
  `.llmbox` walk-up logic).
- Asks the daemon for the list of conversations and session states for
  that project, scoped to the project's container `working_dir`. (It
  does **not** show conversations from arbitrary `~/source` paths even
  if such paths exist on the host — only conversations that correspond
  to the container's mapped working directory are shown.)
- Renders the picker screen described above.
- Renders entries whose running container is bound to a *different*
  host checkout than the one the user invoked `claudebox` from as
  visible-but-disabled, with a note showing the other checkout. The
  daemon refuses the take-over for these and the picker does not
  offer it as an action.
- On selection, asks the daemon to either start or attach, then
  `docker exec`s an attach client into the resulting container. If
  the selection is a *resumable* conversation (no running container)
  whose original checkout differs from the user's current one, the
  CLI surfaces the warn-on-different-checkout rule before proceeding.
- On terminal close, simply exits — the multiplexer inside the container
  keeps Claude alive.

## What the MCP server exposes

A small set of tools intended to be called from claude.ai conversations:

- List projects, with for each: project name, container `working_dir`,
  the set of host checkouts mapped to it (with which are currently
  occupied by a running container), count of resumable conversations,
  count of active sessions.
- List sessions (active and/or resumable) for a project, including for
  each session the host checkout it was originally started from.
- Start a session in a project. The caller may either name a specific
  host checkout, ask the daemon to allocate any free checkout (one
  not currently bound to a running container), or accept the default.
  Optionally resumes a named conversation; resuming follows the
  warn-on-different-checkout rule below.
- Stop a session.

The MCP server runs in the daemon process, behind a bearer token, and
is exposed to the public internet via the user's existing Kubernetes /
NGINX setup (proxying inbound to the dev box). It is registered once in
the user's Claude account, after which any claude.ai conversation can
use it.

## Session-ID linkage (the risky piece)

For the picker UI and the MCP tools to work, the daemon needs to know
the Claude session ID (the file under `~/.claude/projects/<key>/`) for
each container it starts, and it needs to keep that mapping correct as
the session ID changes during the container's lifetime. Claude does
not surface this reliably at startup. The intended approach is a
`SessionStart` hook configured in `~/.claude/settings.json` that writes
the session ID somewhere the in-container supervisor reads and reports
back to the daemon. A fallback is to tail the project's
`~/.claude/projects/` directory after launch and pick up the newest
file.

A working solution must be validated against **all** of the following
scenarios — a hook that fires for some of them but not others is a
silent correctness bug, because the daemon would end up associating a
container with a stale session ID:

- **Completely new Claude session.** Container starts; user has not yet
  typed anything. Note that a session file is only written on the
  first interaction — closing a Claude that was never typed into does
  not produce a "resume with `claude --resume …`" message and does not
  leave behind a session file. From the daemon's perspective this and
  `/clear` should collapse to the same case if `SessionStart` fires
  consistently.
- **Claude launched with `--resume <id>`.** The session ID is known up
  front (we passed it in), so this case is mostly about confirming the
  hook does not contradict what we already know.
- **`/resume` invoked inside Claude.** This switches the session ID
  mid-container. It is not obvious whether `SessionStart` fires here;
  if it does not, the daemon needs another mechanism to notice the
  switch.
- **`/clear` invoked inside Claude.** Effectively starts a fresh
  session inside the same container. Should collapse with the
  "completely new" case if the hook fires.

This is the single biggest unknown in the plan and should be validated
with a small prototype before the rest of the service is built. If it
turns out to be flaky, the picker UX needs rethinking before — not
after — committing to the rest of the architecture.

## Checkouts vs `working_dir` (the other fiddly piece)

Multiple host checkouts can map to the same container `working_dir`.
For example, both `~/source/DesignAssistant` and
`~/source/DesignAssistant-2` may have `.llmbox/docker-compose.yml`
files whose `working_dir` is `/work/DesignAssistant`. From the
container's, Claude's, and `~/.claude/projects/` perspectives these
checkouts are indistinguishable; from the host filesystem's
perspective they are not.

The model: `working_dir` is **identity**. It is the canonical key for
projects, sessions, conversation listings, picker scope, and
container-to-conversation mapping. The host checkout is **metadata** —
it records *which* host filesystem a given container is bind-mounted
from. Each running container is associated with exactly one host
checkout (recorded as a Docker label so the daemon can recover it
after restart). A project (a `working_dir`) may have several checkouts
available, and several containers belonging to one project may each be
bound to a different checkout simultaneously.

This produces a few distinct behaviors:

- **"Start a session on any free checkout."** When starting a new
  session, the caller (local CLI or MCP) can ask the daemon to
  allocate a host checkout that is not currently bound to any running
  container — useful for spinning up a parallel agent without it
  stepping on an in-flight session's filesystem. The caller may also
  name a specific checkout, or accept the default (the only one, or
  the one the local CLI was invoked from). If the caller asked for a
  free checkout and none is free, the call fails — the daemon does
  not multiplex two containers onto the same checkout.
- **Resume warns when the checkout has changed.** Each session
  records the host checkout it was started from. If a request asks to
  resume that session from a different checkout, the daemon refuses
  unless an explicit force flag is set. Rationale: a session in
  flight may reference files, branch state, or untracked work that
  exists in the original checkout but not in the new one. Silently
  resuming under a different filesystem is a quiet correctness
  footgun — Claude will discover the discrepancy by failing to find a
  file, possibly several minutes into a task.
- **Picker scope stays at `working_dir`, not checkout.** Running
  `claudebox` from `DesignAssistant-2` shows conversations that
  originated under `DesignAssistant` too, because they are the same
  project. The warn-on-different-checkout rule above is what makes
  showing them safe.
- **Take-over is also blocked across checkouts.** If the user is in
  checkout B and a running container is bind-mounted from checkout A,
  the daemon refuses the take-over outright — no force flag. Allowing
  it produces a particularly nasty class of confusion: Claude edits
  and "saves" land in checkout A, while the user's host shell is in
  checkout B and shows no changes. The picker still **lists** these
  sessions so the user knows they exist, but renders them disabled
  with an explicit note ("running from `~/source/DesignAssistant`").
  If the user genuinely wants that session, they `cd` to the matching
  checkout and run `claudebox` again.

This is the second of two known-fiddly pieces in the plan, alongside
session-ID linkage. Its failure modes are quiet — the system will
appear to work, then a session will resume into the wrong filesystem
and the user will only notice after Claude can't find a file it
expects. Worth being explicit about up front for that reason.

## Lifecycle semantics

| Action                                | Effect                                                           |
| ------------------------------------- | ---------------------------------------------------------------- |
| Close VSCode terminal / trash-bin     | Detach. Container and Claude keep running.                       |
| Lose SSH / network                    | Detach.                                                          |
| Run `claudebox` again, pick session   | Reattach. Same Claude process, same conversation in flight.      |
| Pick a connected session              | Take over. Previous attach client is forcibly detached.          |
| Pick "new session"                    | Start container, start Claude.                                   |
| Pick a resumable conversation         | Start container, start Claude with resume flag.                  |
| Claude exits cleanly (`/exit`)        | Supervisor exits, container stops, daemon notices.               |
| Explicit "stop" via CLI or MCP        | Container stops.                                                 |
| Daemon crash                          | Containers keep running. Daemon rebuilds state on restart.       |

An idle-timeout for detached containers is optional and not in the
initial scope.

## Distribution

The daemon ships as a Docker image, not as a host-installed binary or
service. It runs as a long-lived container on the dev box (with
appropriate access to the host's Docker, host filesystem paths, and
network), and the local `claudebox` CLI talks to it from the host. The
"how" — which mounts, which env vars, which network mode — is left for
the implementation phase; the "what" is just that container is the
chosen distribution model, consistent with everything else in this
ecosystem already shipping that way.

## Security posture

- The MCP server is internet-exposed and authenticated by bearer
  token. The token is a new credential worth protecting; rotation and
  per-project scoping are nice-to-haves, not blockers.
- The MCP server lets a claude.ai conversation start a process on the
  dev box that runs with `--dangerously-skip-permissions`. This is not
  a meaningfully larger surface than the existing local setup, which
  already runs Claude that way against the user's repos and home
  directory. The only material new risk is theft of the bearer token.

## Non-goals

- Showing conversations from host paths that aren't mapped into the
  container's `working_dir`.
- A custom mobile or desktop UI. claude.ai is the remote UI.
- Kubernetes deployment of Claude instances. CephFS-mapped session
  storage. Dynamically provisioned per-container checkouts.
- Idle-shutdown of detached containers.

## Suggested validation slice (before building the daemon)

A cheap prototype that proves the two riskiest pieces:

1. Run Claude inside `dtach` inside the existing container. Confirm
   that closing and reopening the VSCode terminal reattaches cleanly,
   with no redraw corruption, no lost input, and no zombie processes.
2. Wire a `SessionStart` hook that writes the Claude session ID to a
   known location, and confirm the picker concept works against it.

Both can be done as modifications to the existing `claudebox` script
and `.llmbox/docker-compose.yml`, with no daemon and no MCP server. If
both work, the rest of the plan is execution. If either is flaky, the
plan needs to change before, not after, committing to the daemon
architecture.
