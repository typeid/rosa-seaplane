# TODO: Remove the Remaining Central-Account Steps from the Region Bootstrap

The RC and MC pipelines run in the RC account and no longer access the central
account. The region bootstrap and the ephemeral provider still do two things in
central that can move out. The regional DNS delegation (`region-dns`) stays a
central step by design.

"Account bootstrap" below means the account minting Account Bootstrapping
pipeline (see [Regional Account Minting](docs/design/regional-account-minting.md)),
which already writes RC-account settings such as `/infra/<env>/<region>/ou-path`
(`rosa-seaplane-internal/infra/modules/account-config`).

## 1. ZOA deployment discovery without a central entry

**Today:** the `zoa` CLI finds a deployment through
`/zoa/deployments/<deployment_name>` in central SSM (`us-east-1` plus the
`eu-west-1` replica). The RC Terraform writes that entry into the RC account
only (`terraform/modules/zoa-access/ssm.tf`), and
`scripts/publish-zoa-discovery.sh` copies it to central with central
credentials after the RC pipeline has applied.

**Target:** the CLI discovers deployments regionally, so no central entry
exists. Options, in order of preference:

1. **DNS TXT record** in the regional zone, for example
   `_zoa.<deployment_name>.<environment_domain>`, holding the Access Function
   URL and invoker role ARN. The RC Terraform already owns that zone. The record
   reveals the endpoint and account ID publicly; the endpoint still requires
   IAM auth, but review this before choosing it.
2. **SSM in the RC account** (the parameter the RC Terraform already writes).
   The CLI then needs the RC account per deployment, from config or DNS.

**Needs:** a `rosa-seaplane-zoa` CLI change (it currently reads central SSM).

**Removes:**

- `scripts/publish-zoa-discovery.sh`
- `_publish_zoa_discovery` and its calls in `ci/ephemeral-provider/orchestrator.py`
- step 3.4 in `docs/environment-provisioning.md` and the interim notes in
  `docs/design/codepipeline-cluster-lifecycle.md`,
  `docs/design/zoa-architecture.md`, and `terraform/modules/zoa-access/`

The central account ID still reaches the RC Terraform as a plain value
(`ZOA_CENTRAL_ACCOUNT_ID`), because the ZOA invoker role trusts central's SAML
roles. That needs no access to central and is out of scope here.

## 2. Write `/infra/*/account_id` into the RC account in the account bootstrap

**Today:** rendered configs reference account IDs as
`ssm:///infra/<env>/<region>/.../account_id`. Operators store them in central
SSM, and `bootstrap-region.sh` copies every referenced parameter into the RC
account, where the RC and MC builds resolve them.

**Target:** the account bootstrap writes the RC and MC account IDs for the
region into the RC account's SSM, next to `/infra/<env>/<region>/ou-path`.
Ephemeral environments already render literal account IDs and need nothing.

The bootstrap itself still resolves the RC account ID to know where to deploy,
so central (or the rendered config) keeps that one value.

**Removes:**

- the copy loop in `bootstrap-region.sh`
- the copy note in `docs/design/codepipeline-cluster-lifecycle.md`

## Result

With items 1 and 2 done:

- `bootstrap-region.sh` writes to central only for the DNS delegation
  (`region-dns`).
- The only remaining manual steps per RC account are authorizing the GitHub
  connection and adding the MC CodeBuild role to each MC account's trust policy.
