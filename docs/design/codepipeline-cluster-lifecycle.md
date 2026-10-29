# CodePipeline Cluster Lifecycle

**Status:** Current

Each RC and MC has one CodePipeline invoking a single combined CodeBuild project.
All of a region's pipelines run in that region's RC account. Terraform owns the
region's shared pipeline resources; the cluster resource script owns dynamic
CodeBuild/CodePipeline lifecycle. The platform image is built by Konflux from
`terraform/modules/platform-image/Dockerfile` and referenced by the rendered
`platform_image` config value.

## Why this architecture

The current decision keeps CodePipeline as the per-cluster source and execution
controller, with one combined CodeBuild worker for each RC or MC. This preserves
CodeStar branch and file-path triggers, pipeline variables such as
`IS_DESTROY`, and the provider's ability to adopt, resume, retry, and monitor a
specific pipeline execution. Combining the cluster phases into one CodeBuild
project reduces the stage-specific project and handoff overhead while retaining
those pipeline lifecycle features.

Standalone CodeBuild was considered because it removes CodePipeline resources
and artifact handoffs, and its per-project concurrency limit can serialize
Terraform applies. It replaces CodePipeline source triggers and execution
history with CodeBuild Git webhooks and SDK-managed build lifecycle; the
provider would need to coordinate build adoption, retries, resume, and teardown
around those builds. The current implementation keeps CodePipeline for its
established source and execution semantics; the standalone CodeBuild design is
a superseded proposal, not the selected architecture.

The previous Terraform-managed design used a central provisioner and
Terraform-owned per-cluster pipelines with separate CodeBuild projects for
their stages. The current design keeps the shared central bootstrap in
Terraform but creates and updates dynamic cluster pipelines/projects through
the resource script. That removes per-cluster pipeline definitions from
Terraform state and lets additional MC pipelines be managed without adding
per-MC Terraform state or applies. It trades Terraform's resource tracking for
custom lifecycle and migration handling, so existing environments still need a
reviewed cutover.

This split fits the regional layout: each RC and MC pipeline uses its own
cluster configuration, target-account role, Terraform state, and regional
inputs, while shared central resources remain bootstrapped once. RC and MC
executions can be managed independently; MC waits for its required RC outputs
before completing its dependent work. The combined CodeBuild worker also gives
up stage-level isolation: retrying a failed later phase reruns the earlier
idempotent phases in that cluster build.

## Pipeline account

Pipelines run in the RC account so that RC deploys, MC deploys, and MC scaling
do not depend on a shared central account, and an MC autoscaler in the RC EKS
cluster can manage MC pipelines in its own account. The RC and MC pipelines
have no access to the central account.

`scripts/bootstrap-region.sh` runs from the central account once per RC. It
applies two independent Terraform roots:

- **`region-bootstrap` (RC account, RC credentials, RC state bucket):** the
  GitHub connection, the `codepipeline-shared` module (artifact bucket,
  CodePipeline role, one CodeBuild role for all RC and MC projects), and
  failure notifications.
- **`region-dns` (central credentials, central state bucket):** the regional
  hosted zone in the RC account and its NS delegation in the central
  environment zone, through the `delegated-zone` module. The same module can
  later delegate zone shards in separate accounts from the regional zone.

It also copies the `/infra/*/account_id` SSM parameters referenced by the
rendered build inputs into the RC account, where the builds resolve them.

The ZOA CLI looks deployments up in central SSM (`/zoa/deployments/<name>`).
The RC Terraform writes that entry into the RC account only, and
`scripts/publish-zoa-discovery.sh` copies it to central after the RC pipeline
has applied (the ephemeral provider runs it automatically). This is an interim
step: ZOA discovery needs a rework (rosa-seaplane-zoa CLI) so regions no longer
need a central entry at all.

The CodeBuild role has `AdministratorAccess` in the RC account, matching the
child admin role the builds used to assume there, and MC builds assume the
child admin role in each MC account. As a consequence, administrator access to
the RC account can reach the region's MC accounts through the CodeBuild role.
Protect the pipeline resources and that role with a service control policy on
the region OU (owned by account minting).

## Lifecycle contract

`scripts/provision-cluster-resources.sh` supports:

- `create-rc`, `delete-rc`
- `create-mc`, `delete-mc`

Each action accepts one rendered cluster config from `pipeline-provisioner-inputs/`;
create actions also take `--region-deployment`. The no-argument form applies
the same operations to all rendered clusters for int/stage and ephemeral
bootstrap. Creating a CodePipeline starts one execution automatically; the
cluster resource script does not call `StartPipelineExecution`. Pipeline
resources are not Terraform state, allowing an MC autoscaler to manage them
without Terraform applies or per-MC pipeline state files.

Bootstrap creates the shared Terraform resources and invokes this script
directly. Rerun it through bootstrap when the
cluster set or project/pipeline definitions change; existing pipeline push
filters only trigger infrastructure executions. A project is named after its
rendered `regional_id` or `management_id`, with `-pipeline` appended for the
associated CodePipeline.

## Authorization and ownership

Bootstrap reads the rendered cluster descriptors and resolves SSM account IDs.
The script creates each pipeline and project in the RC account named by the
`regional-cluster.json` next to the cluster's config. Each MC account's child
admin role must trust the CodeBuild role ARN; creating another MC in an
already trusting account does not require a bootstrap rerun.

Each cluster CodeBuild project carries
`ProvisioningScope=<CodePipeline-role-ARN>`. That pipeline role can start, stop,
and inspect builds for the exact configured projects, or dynamic projects
carrying its scope. The lifecycle script
refuses to adopt a project tagged with another scope. This supports custom
`cluster_naming` patterns and dynamic MC names. Worker log groups use
`/aws/codebuild/<pipeline-role-name>/<regional|management>`, independent of the
project name. The exact configured projects' default log groups remain
authorized so running builds can finish while project definitions are updated.

These controls preserve the current bootstrap structure. They do not establish
separate account and environment ownership: deployments that share a pipeline
role also share its project scope, and same-account provisioning retains the
infrastructure permissions needed by upstream. The GitHub connection in
each RC account has Terraform destruction protection and survives ephemeral
teardown. The
provider must successfully detach it from that run's bootstrap state before
destroying the remaining bootstrap resources.

## Execution

Pipelines use a CodeStar connection, branch/file push filters, and V2
`SUPERSEDED` execution mode. Ephemeral push triggers stay enabled. The provider
adopts the execution for the pushed source revision when a pipeline's filters
match, and does not independently start that same revision. On initial
provision it adopts each automatic `CreatePipeline` execution. A resume without
a branch push reuses an active execution at the same SHA or explicitly starts a
retry if the pipeline is idle. Resyncs adopt push-triggered pipelines matched
by changed paths. An unmatched pipeline reuses its previous successful
execution, or is explicitly started if it has no successful execution yet. The
CodeBuild action uses the existing buildspec, service role, and Terraform
state. Ephemeral teardown pins its requested commit and passes `IS_DESTROY=true`
as a pipeline variable. The provider starts the RC and all MC destroy executions
before waiting, so cluster destruction runs concurrently. Full teardown waits
for every execution to succeed before deleting cluster pipelines/projects and
shared bootstrap resources, then deletes the ephemeral branch. A failed
execution or cleanup step stops subsequent cleanup. Teardown first disables
push triggers and drains active executions; failure to establish that condition
prevents destroy executions from starting. Fire-and-forget teardown exits after
starting all destroy executions, without waiting for cluster destruction or
deleting those pipeline/bootstrap resources or the branch.

The ephemeral provider starts or adopts and polls pipelines in the RC account, validates the underlying
CodeBuild `APPLIED=true` and `APPLIED_SHA` contract, collects CodeBuild logs,
and invokes the same per-cluster delete actions during teardown.

## Migration from Terraform-managed pipelines

The previous upstream architecture owns RC/MC pipelines, their stage-specific
CodeBuild projects, and associated roles/buckets in Terraform, with a separate
central pipeline-provisioner. The per-cluster resource script does not migrate
these resources or their state. Running bootstrap is therefore not an automatic
in-place upgrade for an existing environment.

For a disposable ephemeral environment, complete teardown with the revision
that provisioned it before creating a new environment from this architecture.
For a standing environment, prepare and review a migration plan against its
actual state before applying the new central bootstrap:

1. Pause legacy source triggers and wait for active pipeline/build executions
   to finish. Inventory the central bootstrap state and each legacy RC/MC
   pipeline state, and save state backups and resource definitions.
2. Map shared resources that must survive (connection and shared IAM
   resources) to their new Terraform addresses. The central bootstrap includes
   `moved.tf` mappings for the shared MC role. Review these mappings, any additional
   moves/imports needed by the actual environment, and the resulting plan before
   applying.
3. Identify legacy per-cluster pipeline resources separately from target-account
   cluster infrastructure. Retire legacy pipeline resources with their original
   configuration and a reviewed plan, or explicitly transfer ownership of any
   reused resource. Removing a resource from state only stops Terraform tracking
   it; it does not delete a legacy pipeline or disable its trigger. Do not leave
   legacy and new pipelines able to apply to the same cluster concurrently.
4. Preserve the target-account infrastructure state buckets, keys, and cluster
   IDs. Create the new per-cluster resources only after the legacy execution
   path is inactive, then verify that the first execution uses the existing
   infrastructure state and completes successfully.

Environments that separately trialed standalone CodeBuild webhooks also need
those webhook triggers removed before enabling the new CodePipeline triggers.
There is no bundled webhook-cleanup or legacy-state migration script.
