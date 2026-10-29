#!/bin/bash
set -euo pipefail

# =============================================================================
# Publish ZOA Deployment Discovery
# =============================================================================
# The ZOA CLI finds a deployment through /zoa/deployments/<deployment_name> in
# the central account (primary + replica SSM regions). The RC Terraform writes
# that parameter into the RC account only; run this from the central account
# after the RC pipeline has applied, to copy it to central. --delete removes the
# central copies (teardown).
#
# TODO: Rework ZOA deployment discovery so it no longer needs a central entry
# (rosa-seaplane-zoa CLI change), then retire this script.
#
# Usage: publish-zoa-discovery.sh [--delete] <environment> <region-deployment>
# =============================================================================

DELETE=false
if [[ "${1:-}" == "--delete" ]]; then
    DELETE=true
    shift
fi
ENVIRONMENT="${1:?Usage: $0 [--delete] <environment> <region-deployment>}"
REGION_DEPLOYMENT="${2:?Usage: $0 [--delete] <environment> <region-deployment>}"
# The ZOA CLI's primary and replica discovery regions.
CENTRAL_REGIONS="us-east-1 eu-west-1"

DEPLOY_DIR="deploy/${ENVIRONMENT}/${REGION_DEPLOYMENT}"
RC_CONFIG="${DEPLOY_DIR}/pipeline-provisioner-inputs/regional-cluster.json"
DEPLOYMENT_NAME=$(jq -er '.deployment_name' "${DEPLOY_DIR}/pipeline-regional-cluster-inputs/terraform.json")
PARAM="/zoa/deployments/${DEPLOYMENT_NAME}"

if [[ "$DELETE" == "true" ]]; then
    for region in $CENTRAL_REGIONS; do
        if ! out=$(aws ssm delete-parameter --name "$PARAM" --region "$region" --no-cli-pager 2>&1); then
            [[ "$out" == *ParameterNotFound* ]] || { echo "ERROR: $out" >&2; exit 1; }
        fi
        echo "Removed ${PARAM} from central ${region}"
    done
    exit 0
fi

RC_REGION=$(jq -er '.region' "$RC_CONFIG")
RC_ACCOUNT_ID=$(jq -er '.account_id' "$RC_CONFIG")
if [[ "$RC_ACCOUNT_ID" == ssm://* ]]; then
    RC_ACCOUNT_ID=$(aws ssm get-parameter --name "${RC_ACCOUNT_ID#ssm://}" \
        --query 'Parameter.Value' --output text --region "$RC_REGION" --no-cli-pager)
fi
RC_CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${RC_ACCOUNT_ID}:role/$(jq -er '.child_admin_role_name' "$RC_CONFIG")" \
    --role-session-name "publish-zoa-discovery" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text --no-cli-pager)
read -r key secret token <<<"$RC_CREDS"

VALUE=$(env -u AWS_PROFILE AWS_ACCESS_KEY_ID="$key" AWS_SECRET_ACCESS_KEY="$secret" AWS_SESSION_TOKEN="$token" \
    aws ssm get-parameter --name "$PARAM" --query 'Parameter.Value' --output text \
    --region "$RC_REGION" --no-cli-pager)

for region in $CENTRAL_REGIONS; do
    aws ssm put-parameter --name "$PARAM" --value "$VALUE" --type String --overwrite \
        --region "$region" --no-cli-pager >/dev/null
    echo "Published ${PARAM} to central ${region}"
done
