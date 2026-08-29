# Plan: Add Nextcloud as a Family Cloud

## Goal

Add a self-hosted Nextcloud instance that becomes the shared family platform for:

- files and folder sharing
- calendars and contacts
- simple Markdown notes
- collaborative documents and spreadsheets
- future photo backups from the children’s Android tablets

The migration should preserve portability, use the existing GitOps/Ansible model, and include
tested backup and restore paths before important family data is moved.

## Proposed end state

- A dedicated `nextcloud` VM, separate from the busy `services` VM
- A Docker Compose stack containing:
  - Nextcloud
  - MariaDB or PostgreSQL
  - Redis
  - Nextcloud cron/background jobs
  - optional online office service
- A dedicated ZFS dataset for Nextcloud user data, exposed through VirtioFS
- Tailscale installed directly on the Nextcloud VM
- A separate Tailscale machine share for the wife, rather than access to the whole tailnet
- Caddy integration for normal internal routing, without sharing the multi-service `services` VM

## Core user accounts

Create separate, non-admin Nextcloud accounts for:

- the primary user
- the wife
- each child, when needed

Use quotas and explicit shares:

- private personal files remain private
- a shared family folder is available to both adults
- children receive limited quotas and only the folders they need
- shared calendars and notes are owned by an adult account

Nextcloud supports per-user quotas, groups, and configurable file/folder sharing.

## Calendar and contacts

### Calendar migration

1. Export the existing shared Proton calendar.
2. Import it into a shared Nextcloud calendar.
3. Give the wife read/write access.
4. Run both systems temporarily while testing event creation, edits, reminders, and invitations.
5. Make Nextcloud the source of truth after the test period.

Proton Calendar does not provide direct two-way CalDAV synchronization, so Proton and Nextcloud
should not be treated as synchronized copies.

### Client access

- Android: DAVx5 plus the preferred Android calendar application
- iPhone: native Apple Calendar through CalDAV
- GNOME: GNOME Online Accounts, Evolution, or the GNOME Calendar app

Contacts use the same pattern through CardDAV:

- Android: DAVx5 plus the Android Contacts provider
- iPhone: native Apple Contacts through CardDAV
- GNOME: Evolution/GNOME Contacts

## Notes and Obsidian

Because the existing Obsidian vault is simple Markdown, Nextcloud is a realistic replacement for
CouchDB LiveSync as the synchronization backend.

Recommended approach:

- keep Obsidian as the primary editor
- synchronize the vault through Nextcloud/WebDAV using a tested community plugin
- use Nextcloud Notes or another client for lightweight access
- use Iotas on GNOME if its workflow is preferred
- keep the existing LiveSync setup until multi-device conflict testing succeeds

Shared household notes can use Nextcloud Text or a shared Markdown folder. Avoid having multiple
clients edit the same vault simultaneously until their conflict and attachment behavior is known.

## Office documents and spreadsheets

### Online collaboration

Evaluate Nextcloud Office with Collabora or the newer Euro-Office option for shared browser-based
editing of documents, spreadsheets, and presentations.

Important consideration: the Collabora option is LibreOffice-derived. It may provide a better
browser interface, but it is not technically unrelated to LibreOffice.

### Offline editing

Use the Nextcloud Desktop Client to keep selected folders locally available. Open those files with
the preferred offline application, such as:

- SoftMaker FreeOffice/Office for a different interface and strong Microsoft format support
- Calligra for an open-source offline option
- Collabora Office if its LibreOffice-derived interface is acceptable

Use the online office service when two people need to edit the same file simultaneously. Editing
the same file offline on multiple devices may result in conflict copies.

## Children’s tablets and photo backup

When the tablets become more active:

1. Create one account per child.
2. Configure quotas.
3. Install the Nextcloud Android client.
4. Enable automatic upload for camera and screenshot folders.
5. Upload into separate folders such as `Children/<name>/Photos`.
6. Share selected family folders back to the adults.

Nextcloud can act as the upload and backup destination. Immich should remain the preferred photo
library interface unless a deliberate Nextcloud-to-Immich import workflow is designed. Do not let
both systems independently manage the same live photo directory without testing.

## Storage and backup design

Use a dedicated dataset such as `storage/nextcloud` rather than placing primary Nextcloud data in
the general `storage/smb` dataset.

Back up:

- Nextcloud database dumps
- `config.php`
- installed apps and custom configuration
- user data
- calendar and contact data through the database and regular exports
- Compose files and Ansible variables

Add the new dataset to:

- Sanoid snapshot configuration
- Syncoid replication to the off-site backupserver
- offline backup procedures where appropriate

Before migration, perform a restore test on a disposable instance or VM.

## Implementation phases

### Phase 1 — Pilot foundation

- Create the dedicated VM and storage dataset.
- Add the `nextcloud` Ansible role and playbook.
- Deploy Nextcloud, database, Redis, and cron.
- Configure Tailscale access and basic monitoring.
- Test rebuild and restore before importing family data.

### Phase 2 — Files and accounts

- Create adult accounts.
- Configure quotas and family shares.
- Test Android, iPhone, GNOME, and desktop sync clients.

### Phase 3 — Calendar and contacts

- Import a copy of the Proton calendar.
- Test shared editing from Android and iPhone.
- Test contacts through DAVx5 and Apple CardDAV.
- Configure SMTP for invitations and notifications.

### Phase 4 — Notes

- Copy the Obsidian vault into a controlled test folder.
- Test the selected sync plugin across desktop and Android.
- Test offline edits, simultaneous edits, renames, deletions, and attachments.
- Test Iotas or Nextcloud Notes for lightweight access.

### Phase 5 — Office and children

- Add online office only after the core service is stable.
- Test collaborative documents and spreadsheets.
- Add child accounts and photo upload rules later.

### Phase 6 — Retire replaced services

- Retire Proton Calendar only after a successful parallel run.
- Retire CouchDB LiveSync only after notes restore and conflict testing.
- Keep exported calendar, contacts, and Markdown backups outside Nextcloud.

## Main risks

- Nextcloud is more operationally complex than CouchDB or a basic file server.
- Mobile background uploads can be delayed by Android or iOS power management.
- Tailscale must remain connected for devices to sync if the service is private-only.
- Optional apps have different levels of maintenance and quality.
- Office integration adds CPU, memory, reverse-proxy, and upgrade complexity.
- Shared Markdown editing is not the same as real-time collaborative office editing.

## Success criteria

- The whole VM can be rebuilt without losing user data.
- The database and files can be restored independently and together.
- The wife can use the shared calendar from Apple Calendar without seeing other services.
- Android calendar, contacts, notes, and photo uploads work reliably.
- The Obsidian vault survives offline edits and conflict testing.
- Shared documents and spreadsheets can be edited online and offline with a documented workflow.
- Child accounts can be added without changing the underlying architecture.

## References

- [Nextcloud Android synchronization](https://docs.nextcloud.com/server/26/user_manual/en/groupware/sync_android.html)
- [Nextcloud iOS synchronization](https://docs.nextcloud.com/server/stable/user_manual/en/groupware/sync_ios.html)
- [Nextcloud Office](https://docs.nextcloud.com/server/stable/admin_manual/office/index.html)
- [Nextcloud Notes](https://github.com/nextcloud/notes)
- [Iotas](https://apps.gnome.org/en/Iotas/)
