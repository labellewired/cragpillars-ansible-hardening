# CragPillars — Ansible Linux Hardening

CragPillars is a homelab project for provisioning and hardening a small **CentOS Stream 10** environment using **Kickstart** and **Ansible**. It combines repeatable operating-system installation, network segmentation, centralized infrastructure services, and host-level security controls.

The environment consists of three VMware virtual machines: a Bastion/Ansible controller, a Web server, and an Infrastructure server. It was adapted from an existing working lab; the renamed CragPillars configuration and revised dual-interface Kickstarts still require end-to-end validation.

> **Lab project:** This repository is intended for learning and demonstration, not direct production deployment. Review the security limitations and replace all sample credentials, SSH keys, addresses, and certificates before reuse.

## Architecture

Each VM has two network interfaces:

- **Public network:** `ens33`, `10.10.1.0/24`, with gateway `10.10.1.2`.
- **Administration network:** `ens36`, `10.10.10.0/24`, without a default gateway.

| Server         | Hostname                | Public/ens33 | Admin/ens36   | Primary roles                     |
|----------------|-------------------------|--------------|---------------|-----------------------------------|
| Bastion        | `bastion.crag.internal` | `10.10.1.10` | `10.10.10.10` | SSH access, Ansible control node  |
| Web            | `web.crag.internal`     | `10.10.1.20` | `10.10.10.20` | Nginx, PHP-FPM, and local MariaDB |
| Infrastructure | `infra.crag.internal`   | `10.10.1.40` | `10.10.10.40` | DNS, NTP, central logs, auditing  |

The lab also defines a public client (`10.10.1.200`) and an administration workstation (`10.10.10.100`). `www.cragpillars.com` is a **lab web hostname placeholder**; using it outside the lab requires appropriate DNS configuration.

The editable network diagram is available at [docs/diagrams/architecture.drawio](docs/diagrams/architecture.drawio).

## What the project configures

### Kickstart provisioning

The three Kickstart files provide a minimal CentOS Stream 10 installation, initial `crag_admin` administrator account, static networking, SSH, SELinux enforcing mode, and VMware guest utilities. The revised installation plan configures **both network interfaces before Ansible runs**, avoiding a mid-playbook switch from public to administration networking.

### Common Ansible configuration

- Hostnames, administrator account, and authorized SSH key
- SELinux enforcing mode and SSH hardening, an SSH login banner, and MFA for administrators
- Firewalld zones separating public and administration traffic
- Persistent systemd journal and sudo logging
- Kernel address-space layout randomization (ASLR)
- Required repositories, packages, and services

### Bastion

- Ansible control node
- SSH public-key and TOTP authentication for administrators, with a key-only automation exception for Bastion-to-Web/Infra
- Fail2ban for SSH
- Chrony and rsyslog forwarding to the Infrastructure server

### Web

- Nginx with HTTP-to-HTTPS redirection and a self-signed TLS certificate
- PHP-FPM and a small PHP login application
- MariaDB bound to `127.0.0.1`, with a restricted application database user
- HTTP Basic Authentication configuration for `/admin`

### Infrastructure

- BIND authoritative DNS for `crag.internal`
- Chrony time service
- TCP rsyslog collection from Bastion and Web
- Auditd rules for sensitive configuration files

The repository also includes `ansible/audit.yml`, which installs OpenSCAP components and checks for the expected CentOS Stream 10 SCAP datastream. **It prepares for an audit; it does not itself run a CIS compliance scan or establish compliance.**

## Repository structure

```
cragpillars-ansible-hardening/
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini
│   ├── run.yml
│   ├── audit.yml
│   ├── collections/requirements.yml
│   ├── group_vars/all/
│   │   ├── vars.yml
│   │   └── secrets.yml.example
│   ├── host_vars/
│   ├── handlers/main.yml
│   ├── tasks/
│   └── templates/index.php.j2
├── kickstarts/
│   ├── bastion_srv.ks
│   ├── web_srv.ks
│   └── infra_srv.ks
├── docs/diagrams/
│   ├── architecture.drawio
│   └── architecture.svg
├── .gitignore
├── LICENSE
└── README.md
```

`ansible/group_vars/all/secrets.yml` is an encrypted local file and is excluded from Git by `.gitignore`. Do not publish the file or its plaintext contents.

## Requirements

- Three VMware virtual machines with two correctly attached virtual NICs per server
- CentOS Stream 10 installation media
- Network access between Bastion and the administration interfaces of Web and Infrastructure
- Ansible Core (installed automatically by the Bastion Kickstart). Additional Ansible collections must be   installed using `ansible/collections/requirements.yml`
- A valid SSH public key and appropriate credentials for `crag_admin`
- Internet/repository access for package installation where required

The Kickstarts assume the installation disk is named **`sda`** and include a destructive `clearpart --all` directive. **Review the target disk before using them.** Alternative disk and installation-source options are intentionally retained as comments for customization.

## Deployment outline

These steps describe the intended workflow; they are **not yet a verified, one-command deployment procedure** for the refactored project.

1. Create the three VMs and attach `ens33` to the public network and `ens36` to the administration network. Check VMware interface naming and disk selection.
2. Install CentOS Stream 10 using the provided Kickstarts. Review the files in `kickstarts/` and generate a password hash using `openssl passwd -6`. Replace `REPLACE_WITH_PASSWORD_HASH` in each file with the resulting hash. Use a unique, disposable lab password. Install CentOS Stream 10 on each VM using its corresponding Kickstart file:
Bastion: `kickstarts/bastion_srv.ks`
Web:     `kickstarts/web_srv.ks`
Infra:   `kickstarts/infra_srv.ks`
Each Kickstart can be supplied to the installer using the `inst.ks=` boot option followed by the URL of the hosted file. For detailed instructions, see the official Red Hat Enterprise Linux 10 Kickstart installation documentation.
3. Confirm the expected addresses and connectivity on both interfaces. In particular, Bastion must reach `10.10.10.20` and `10.10.10.40` over SSH.
4. Clone the repository onto Bastion, which serves as the Ansible control node, and navigate to the `ansible/` directory.
   ```bash
   sudo dnf install git -y
   git clone https://github.com/YOUR_USERNAME/cragpillars-ansible-hardening.git
   cd cragpillars-ansible-hardening/ansible
   ```
5. Install the required Ansible dependencies:
   ```bash
   sudo dnf install sshpass -y
   ansible-galaxy collection install -r collections/requirements.yml
   ```
6. Configure Ansible Vault using `group_vars/all/secrets.yml.example` as a reference that contains placeholders. Create `group_vars/all/secrets.yml`, replace the required secrets with your own password hash, TOTP secret, database password, and web credentials, then encrypt it:
   ```bash
   cp group_vars/all/secrets.yml.example group_vars/all/secrets.yml
   nano group_vars/all/secrets.yml
   ansible-vault encrypt group_vars/all/secrets.yml
   ```
7. Replace the example **crag_admin** SSH public key (crag_admin_ssh_public_key) in `group_vars/all/vars.yml` and review all IP addresses, hostnames, and workstation restrictions for your environment.
8. Review `inventory.ini` and verify the Ansible connection method. Bastion uses a local connection; Web and Infrastructure are reached through their administration IPs. Ensure that `crag_admin` can connect from Bastion to both remote servers over SSH and has sudo privileges on all three servers.
9. From `ansible/`, run the deployment playbook. On its **first run**, it uses the Kickstart SSH password to install a dedicated Ed25519 automation key on Bastion and authorize it on Web/Infra **before** enabling the final SSH/MFA restrictions. It also enrolls the TOTP secret from Vault on all three hosts. Do not interrupt the first run during SSH/firewall changes:
   ```bash
   ansible-playbook run.yml -u crag_admin --ask-pass --ask-become-pass --ask-vault-pass
   ```
10. **Subsequent runs** use Bastion's dedicated automation key, not the Kickstart SSH password. Run as `crag_admin` on Bastion:
    ```bash
    ansible-playbook run.yml -u crag_admin --private-key ~/.ssh/id_ed25519_ansible --ask-become-pass --ask-vault-pass
    ```
    To prepare the OpenSCAP tooling, use the same key:
    ```bash
    ansible-playbook audit.yml -u crag_admin --private-key ~/.ssh/id_ed25519_ansible --ask-become-pass --ask-vault-pass
    ```
    **Bootstrap limitation:** The first deployment still depends on password-based SSH from the Kickstarts and has not been end-to-end tested. Ensure the administrator's public key and Vault TOTP seed are valid before deploying. Keep console access available for recovery.

**Important:** The Kickstarts deliberately contain the `REPLACE_WITH_PASSWORD_HASH` placeholder instead of a working administrator password hash. Generate and insert a valid hash locally before installing. Do not commit your customized Kickstarts with real credentials. `ansible.cfg` also disables SSH host-key checking for this lab; verify and pin host keys before treating this as a trusted environment. Do not carry that setting into an untrusted or production environment.

## SSH access policy

Only the following IPv4 SSH paths are intended to be permitted by firewalld:

| Source         | Destination              | Authentication                    |
|----------------|--------------------------|-----------------------------------|
| `10.10.1.200`  | `crag_admin@10.10.1.10`  | Public key + TOTP                 |
| `10.10.10.100` | `crag_admin@10.10.10.10` | Public key + TOTP                 |
| `10.10.10.100` | `crag_admin@10.10.10.20` | Public key + TOTP                 |
| `10.10.10.100` | `crag_admin@10.10.10.40` | Public key + TOTP                 |
| `10.10.10.10`  | `crag_admin@10.10.10.20` | Dedicated Ansible public key only |
| `10.10.10.10`  | `crag_admin@10.10.10.40` | Dedicated Ansible public key only |

The playbook generates `/home/crag_admin/.ssh/id_ed25519_ansible` on Bastion if absent, and installs its public key on Web and Infra. The private key stays on Bastion. The automation exception is scoped by SSH source and destination addresses, not by the SSH key itself; protect Bastion and its `crag_admin` credentials accordingly.

All servers disable root SSH, password-only authentication, TCP forwarding, SSH agent forwarding, X11 forwarding, and tunnel devices. `ProxyJump` and SSH TCP tunnels through Bastion are intentionally unavailable. To reach Web/Infra from the public workstation, first SSH into Bastion, then initiate a separate SSH session from Bastion. The SSH login banner is managed at `/etc/ssh/banner.txt`.

**Validation required:** Confirm `sshd -T -C` effective settings for each connection source and test both permitted and denied paths. `MaxAuthTries 3` limits SSH authentication failures per connection; Google Authenticator also limits TOTP attempts to three per 30 seconds. TOTP secrets shared across hosts are a lab simplification, not a production recommendation.

## Security considerations and limitations

- **Kickstart credentials are intentionally omitted.** Each file uses `REPLACE_WITH_PASSWORD_HASH` for `crag_admin`. Replace it with a locally generated SHA-512 crypt hash before installation; do not publish the customized files or reuse the installation password outside the lab.
- The application currently uses **unsalted SHA-256 password hashes** for its login table. This should be replaced with PHP `password_hash()` / `password_verify()` and corresponding database provisioning before production use.
- Nginx uses a **self-signed TLS certificate**. Browsers will not automatically trust it.
- Review the `/admin` Nginx routing and authentication behavior as part of functional security testing.
- Review the permissions and handling of the rendered PHP application, which contains a database credential.
- Firewall policy, SSH MFA, DNS, logging, and Ansible idempotence still need verification after the refactor. Configuration files express intended behavior, not proof of successful enforcement.
- The architecture and IP addresses are specific to a private VMware lab.

## Project status

**Current stage: refactoring and preparing the repository for its first public commit.**

The original lab operated with Kickstart provisioning and Ansible configuration. The CragPillars refactor updates naming, secrets handling, documentation, and the installation network layout. The revised Kickstarts, Ansible deployment, web login flow, and security controls have **not yet been fully retested together**.

Planned next steps include a repository-wide consistency/security review, validation of the Kickstarts, a clean installation test, and end-to-end Ansible verification.

## License

See [LICENSE](LICENSE) for the repository license.