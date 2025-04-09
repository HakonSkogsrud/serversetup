# Server setup

Ansible playbooks for homelab. Currently I use Alma linux.

Run files like this
```sh
ansible-playbook -i inventory.yml --ask-vault-pass -K samba-setup.yml
```

## Setup

Playbooks require passwordless ssh to server.

```sh
brew install ansible ansible-lint

ansible-galaxy collection install community.general --force
ansible-galaxy collection install ansible.posix --force
```
## Development

```sh
uv venv
uv pip install -r requirements.txt
pre-commit install
````

Before commit run

```sh
pre-commit run --all-files
```

Add a file `.vault_pass` with vault password
