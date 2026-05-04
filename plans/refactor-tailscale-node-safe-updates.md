# Plan: Make Tailscale Node Updates Safer

## Goal

Refactor the `tailscale_node` role so normal playbook runs do not use `tailscale up --reset` on already-connected remote machines. The role should use `tailscale up` only for first login or explicit re-auth, and `tailscale set` for routine preference changes like hostname or route acceptance.

## Problem

Current behavior in `roles/tailscale_node/tasks/tailscale_node.yml` always runs:

```bash
tailscale up --authkey=... --hostname=... [--accept-routes] --reset
```

That works, but it is riskier than necessary on remote hosts because:

- it re-applies the full Tailscale session even when the node is already healthy
- it depends on auth and control-plane state during a live remote change
- a mistake in flags or auth could interrupt remote access

This became visible while enabling route acceptance on `backupserver` so it could reach Uptime Kuma on `10.0.0.44`.

## Desired Behavior

### New install or logged-out node

Use `tailscale up` with auth key and required options.

### Existing healthy node

Use `tailscale set` for mutable settings such as:

- hostname
- `accept-routes`

### Explicit destructive update

Allow reset/re-auth only when a dedicated variable is set, for example:

```yaml
tailscale_node_force_reset: false
```

## Proposed Role Behavior

1. Read current Tailscale status with `tailscale status --json`
2. Parse backend state (`Running`, `NeedsLogin`, etc.)
3. If not running, use `tailscale up`
4. If already running, use `tailscale set`
5. Only use `--reset` when `tailscale_node_force_reset: true`

## Planned Variable Interface

In `roles/tailscale_node/defaults/main.yml`:

```yaml
tailscale_node_hostname:
tailscale_node_accept_routes: false
tailscale_node_force_reset: false
```

## Implementation Steps

1. Update `roles/tailscale_node/defaults/main.yml`
   Add `tailscale_node_force_reset: false`

2. Refactor `roles/tailscale_node/tasks/tailscale_node.yml`
   Add a status probe using `tailscale status --json`

3. Parse current state
   Use `set_fact` to determine whether the node is already running

4. Split the current single task into two paths
   - `tailscale up` path for new login / forced reset
   - `tailscale set` path for existing connected nodes

5. Keep route acceptance configurable
   Continue supporting `tailscale_node_accept_routes`

6. Preserve current `backupserver` behavior
   Ensure `backupserver` still accepts subnet routes so it can reach Uptime Kuma on the services subnet

## Example Target Shape

```yaml
- name: Read Tailscale status
  ansible.builtin.command: tailscale status --json
  register: tailscale_status
  changed_when: false
  failed_when: false

- name: Parse backend state
  ansible.builtin.set_fact:
    tailscale_backend_state: "{{ (tailscale_status.stdout | from_json).BackendState | default('NeedsLogin') }}"
  when: tailscale_status.rc == 0

- name: Login or force reset
  ansible.builtin.command: >
    tailscale up
    --authkey={{ tailscale_auth_key }}
    --hostname={{ tailscale_node_hostname }}
    {% if tailscale_node_accept_routes | bool %}--accept-routes{% endif %}
    {% if tailscale_node_force_reset | bool %}--reset{% endif %}
  when:
    - tailscale_backend_state | default('NeedsLogin') != 'Running' or tailscale_node_force_reset | bool

- name: Update existing node preferences
  ansible.builtin.command: >
    tailscale set
    --hostname={{ tailscale_node_hostname }}
    --accept-routes={{ 'true' if tailscale_node_accept_routes | bool else 'false' }}
  when:
    - tailscale_backend_state | default('NeedsLogin') == 'Running'
    - not tailscale_node_force_reset | bool
```

## Validation Plan

1. Test on `backupserver`
   Confirm route acceptance remains enabled and `disk_health` can still push to Uptime Kuma

2. Test on an already-connected non-critical node
   Confirm playbook run does not force re-auth and does not interrupt Tailscale connectivity

3. Test first-login path separately
   Only on a disposable or newly provisioned node

4. Verify idempotence
   A second playbook run should result in no change unless preferences differ

5. Verify rollback behavior
   Setting `tailscale_node_accept_routes: false` should remove accepted routes without forcing a reset

## Risks

- `tailscale set` may not support every option currently passed to `tailscale up`
- state parsing must tolerate `tailscale status --json` failing on logged-out nodes
- changing accepted routes on remote hosts still affects reachability, but it is lower risk than resetting the full session

## Success Criteria

- normal playbook runs on existing nodes do not use `--reset`
- `backupserver` still reaches Uptime Kuma successfully
- no regression for first-time node registration
- repeated runs are idempotent and lower-risk for remote management