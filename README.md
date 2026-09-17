# AWX Learning Project — Terraform + AWS + AWX

A small, self-contained pipeline for learning Ansible AWX (and, by
extension, Ansible Automation Platform / Tower — AWX is its upstream
open-source project) by building something that resembles how it's used
in production: infrastructure provisioning and configuration management
both driven from AWX, not from a laptop terminal.

## What this demonstrates

| AWX/Tower concept | Where it shows up here |
|---|---|
| Projects (SCM sync) | Pulls this repo, auto-installs Ansible collections on sync |
| Credentials (Machine, Cloud, Vault, SCM) | AWS, SSH, and Vault-encrypted secrets, kept out of git entirely |
| Dynamic Inventory | `amazon.aws.aws_ec2` source — no IP ever typed in by hand |
| Job Templates | One per pipeline stage: provision, destroy, ping, configure |
| Surveys | Runtime prompt on the configure step |
| Workflow Templates | Chains the stages into one push-button run |
| Custom Execution Environments | Adds the `terraform` binary to the AWX runtime image |
| Ansible Vault | Encrypts one real secret used by the nginx role |

## Architecture

```
                      ┌─────────────────────┐
                      │   AWX (on my Mac)    │
                      └──────────┬───────────┘
                                 │ Workflow Template
        ┌────────────────────────┼─────────────────────────┐
        ▼                        ▼                          ▼
 ┌───────────────┐      ┌────────────────┐        ┌──────────────────┐
 │ tf-provision   │─────▶│ inventory sync │───────▶│ ping-nodes        │
 │ (Terraform     │      │ (amazon.aws    │        │ configure-nginx   │
 │  apply, via    │      │  dynamic       │        │ (Ansible role,    │
 │  custom EE)    │      │  inventory)    │        │  Vault secret)    │
 └───────────────┘      └────────────────┘        └──────────────────┘
        │                                                    │
        ▼                                                    ▼
   AWS: EC2 + SG                                    Configured web nodes
```

Nobody runs `terraform apply`, `terraform destroy`, or `ansible-playbook`
by hand at any point — every stage above is an AWX Job Template, and the
Workflow Template chains them into a single click.

## Repo layout

```
terraform/                     Infra definition: EC2 instances + security group
  main.tf / variables.tf / terraform.tfvars.example

bootstrap/                     Run ONCE, locally: creates the EC2 key pair
                                so there's no AWS Console click needed
  main.tf / variables.tf / versions.tf

ansible/
  requirements.yml             Collections AWX auto-installs on Project sync
  ansible.cfg
  inventory/aws_ec2.yml        AWX dynamic inventory source
  playbooks/
    1-terraform-provision.yml  Runs `terraform apply` (cloud.terraform.terraform)
    2-terraform-destroy.yml    Runs `terraform destroy`
    3-ping.yml                 Connectivity check against new nodes
    4-install-nginx.yml        Configures nginx via the webserver role
  roles/webserver/             nginx install + optional Vault-secured basic auth
  group_vars/all/
    vault.yml.example              Template for the one Vault-encrypted secret
    terraform_backend.yml.example  Template for the S3/DynamoDB state backend config

execution-environment/         Custom AWX EE definition (adds the `terraform` binary)
```

## Prerequisites

- AWX running and reachable (already set up locally)
- An AWS account and an existing access key/secret with EC2 permissions
- `ansible-builder` + Docker/Podman, to build the custom Execution Environment

## Setup

### 1. Bootstrap the AWS key pair + remote state backend (once)

`bootstrap/` does two things AWS Console would otherwise be needed for:

- generates an SSH keypair and registers it as an EC2 Key Pair
- creates an **S3 bucket (versioned, encrypted, private) and a DynamoDB
  table** for Terraform's remote state — so `terraform/` never keeps
  state as a local file

```bash
cd bootstrap
terraform init
terraform apply
```

This writes the private key to `bootstrap/awx-learning-key.pem`
(git-ignored — paste it into an AWX Machine credential in Step 4 below).

Then wire the bucket/table into the main config:

```bash
terraform output -raw tf_state_bucket
terraform output -raw tf_state_dynamodb_table

cd ../ansible/group_vars/all
cp terraform_backend.yml.example terraform_backend.yml
# edit terraform_backend.yml with the two output values above
```

`terraform_backend.yml` isn't secret (it's just a bucket/table name) —
commit it along with everything else so AWX's Job Templates can read it.

### 2. Push this repo to git

AWX Projects sync from source control:

```bash
git init && git add . && git commit -m "initial AWX learning project"
git remote add origin <your-repo-url> && git push -u origin main
```

### 3. Build the custom Execution Environment

The stock AWX EE has no `terraform` binary:

```bash
cd execution-environment
ansible-builder build -t awx-ee-terraform:latest -f execution-environment.yml
```

Push it to a registry AWX can reach, then add it under
**Administration → Execution Environments**.

### 4. AWX Credentials (one manual step)

**Resources → Credentials → Add**, three times:

| Name | Type | Value |
|---|---|---|
| `aws-learning-creds` | Amazon Web Services | your AWS access key ID / secret access key |
| `aws-learning-ssh` | Machine | paste the contents of `bootstrap/awx-learning-key.pem` |
| `aws-learning-vault` | Vault | the password you'll use with `ansible-vault` below |

This is the only UI step left in the whole pipeline — everything after
this point is driven by AWX itself.

### 5. AWX Project

**Resources → Projects → Add** — SCM Type Git, SCM URL your repo, enable
"Update Revision on Launch". On sync, AWX reads `ansible/requirements.yml`
and installs `cloud.terraform`, `amazon.aws`, and `ansible.posix`
automatically.

### 6. AWX Inventory

**Resources → Inventories → Add**, then a **Source**: "Sourced from a
Project", inventory file `ansible/inventory/aws_ec2.yml`, credential
`aws-learning-creds`, "Update on Launch" enabled. This is what finds the
EC2 instances Terraform creates, by tag, with no IP ever typed manually.

### 7. Job Templates

| Name | Playbook | Inventory | Credentials | EE |
|---|---|---|---|---|
| `tf-provision` | `1-terraform-provision.yml` | any | `aws-learning-creds` | `awx-ee-terraform` |
| `tf-destroy` | `2-terraform-destroy.yml` | any | `aws-learning-creds` | `awx-ee-terraform` |
| `ping-nodes` | `3-ping.yml` | `awx-learning-inv` | `aws-learning-ssh` | default |
| `configure-nginx` | `4-install-nginx.yml` | `awx-learning-inv` | `aws-learning-ssh`, `aws-learning-vault` | default |

Add a Survey on `configure-nginx` prompting for `enable_basic_auth`.

### 8. Workflow Template

Chain: `tf-provision → (inventory sync) → ping-nodes → configure-nginx`.
`tf-destroy` stays a separate, on-demand template for teardown.

### 9. Launch

Run the workflow. One traceable AWX job with full logs takes you from
"no infrastructure" to "configured, reachable web server" — with only
the Step 1 and Step 4 setup done by hand, once.

## Vault-secured secrets

```bash
cd ansible/group_vars/all
cp vault.yml.example vault.yml
# edit vault.yml — replace CHANGEME with a real password
ansible-vault encrypt vault.yml
```

Commit the encrypted file. The `aws-learning-vault` AWX credential
(created in Step 4) decrypts it in-memory at job run time — the same
mechanism used against real secrets in production Tower environments.

## Production considerations

This is a learning project, and a senior reviewer will reasonably ask
"would you ship it this way?" — the honest answer is: not quite as-is.
What would change for production:

- **SSH keys → AWS Systems Manager Session Manager.** Static key pairs
  and open port 22 are the pattern being phased out industry-wide. The
  SSM connection (`community.aws.aws_ssm`) authenticates via IAM
  instead, needs no key material, and needs no inbound SSH rule at all.
- **Terraform-drives-Ansible, not the other way around.** Red Hat and
  HashiCorp jointly maintain `terraform-provider-aap`, which lets
  Terraform launch an AWX/AAP Job Template as part of `terraform apply`
  (`aap_job_launch`). That's the officially supported integration
  direction. This repo does the reverse — AWX runs Terraform via the
  `cloud.terraform.terraform` module — which works but isn't the
  primary pattern Red Hat designs around.
- **Static AWS keys → OIDC federation.** A CI pipeline (GitHub
  Actions/GitLab CI) would assume an IAM role via OIDC rather than
  storing a long-lived access key/secret anywhere, including in AWX
  credentials.
- **`0.0.0.0/0` defaults → least-privilege security groups**, scoped to
  known CIDRs, with SSH removed entirely once SSM is in place.

## Where this maps to Ansible Tower

Projects, Credentials (Machine/Cloud/Vault/SCM), dynamic Inventory
Sources, Job Templates, Surveys, Workflow Templates, and custom
Execution Environments are identical concepts in Ansible Tower — AWX is
upstream Tower. This repo is directly reusable against a licensed Tower
instance with no structural changes.
