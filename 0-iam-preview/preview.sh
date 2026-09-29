#!/usr/bin/env bash
# Preview every IAM role, policy and permission 1-connect-clumio would create in your AWS
# account, BEFORE anything is created, and check whether the deploy role may create
# them. Uses 1-connect-clumio's own settings (terraform.tfvars), variables and versions, so
# what you approve is what gets created.
#
#   ./preview.sh [--connect ../1-connect-clumio] [--as <role ARN>]
#
# Account and region come from 1-connect-clumio's terraform.tfvars; log in to that account.
# --as checks another identity (e.g. the CI/CD deploy role) instead of your own login.
# Runs `terraform plan` only, in a throwaway folder that is deleted afterwards, so there
# is nothing left to apply. Needs: a read-only AWS login, terraform, python3.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONNECT="$HERE/../1-connect-clumio"
AS_ARN=""
OUT=""
FINISHED=0

fail() { echo "FAIL: $*" >&2; exit 1; }
usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
value() { [ $# -ge 2 ] && [ -n "$2" ] || fail "$1 needs a value (see --help)"; }   # works on macOS bash 3.2

while [ $# -gt 0 ]; do
  case "$1" in
    --connect) value "$@"; CONNECT="$2"; shift 2 ;;
    --as)      value "$@"; AS_ARN="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)         fail "unknown option: $1 (see --help)" ;;
  esac
done

# --- Check inputs before touching anything -------------------------------------
for f in main.tf variables.tf versions.tf terraform.tfvars; do
  [ -f "$CONNECT/$f" ] || fail "$CONNECT/$f not found (point --connect at the 1-connect-clumio folder)"
done
# The module version is pinned in 1-connect-clumio/main.tf, on the line after its source.
MODULE_VERSION="$(awk '/source *= *"clumio-code\/aws-template\/clumio"/ { getline; print }' "$CONNECT/main.tf" \
  | sed -nE 's/^ *version *= *"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p')"
[ -n "$MODULE_VERSION" ] || fail "no exact module version found in $CONNECT/main.tf (expected version = \"x.y.z\" under the aws-template source)"
# A backend here would make the preview plan against real state and drop replacements silently.
! grep -q 'backend *"' "$CONNECT/versions.tf" || fail "$CONNECT/versions.tf has a backend block: move it to backend.tf"
command -v terraform > /dev/null || fail "terraform not found"
command -v python3 > /dev/null   || fail "python3 not found"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || fail "no AWS login (a read-only one is enough)"

WORK="$(mktemp -d)"
# The config never outlives the run; a pack that didn't finish is removed, never left half-written.
trap 'rm -rf "$WORK"; [ "$FINISHED" = 1 ] || [ -z "$OUT" ] || rm -rf "$OUT"' EXIT

# --- A throwaway config: Clumio's module with 1-connect-clumio's settings ------
# Same versions.tf, variables.tf (and its checks) and terraform.tfvars as 1-connect-clumio.
# Values Clumio issues at connect time get stand-ins (they must match extract.py), so every
# document renders. The Clumio provider can never reach Clumio.
cp "$CONNECT/versions.tf" "$CONNECT/variables.tf" "$CONNECT/terraform.tfvars" "$WORK/"
[ ! -f "$CONNECT/.terraform.lock.hcl" ] || cp "$CONNECT/.terraform.lock.hcl" "$WORK/"   # same provider builds as step 1
cat > "$WORK/main.tf" <<'EOF'
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
}
provider "clumio" {
  clumio_api_token    = "preview-only"
  clumio_api_base_url = "https://preview.invalid"
}
module "clumio" {
  source                     = "clumio-code/aws-template/clumio"
  version                    = "MODULE_VERSION"
  clumio_token               = "PREVIEWCLUMIOTOKEN"
  role_external_id           = "PREVIEWEXTERNALID"
  clumio_aws_account_id      = "111111111111"
  data_plane_account_id      = "222222222222"
  aws_account_id             = var.account_id
  aws_region                 = var.region
  iam_entities_identifier    = var.iam_prefix
  path                       = var.iam_path
  is_s3_enabled              = contains(var.workloads, "s3")
  is_rds_enabled             = contains(var.workloads, "rds")
  is_ebs_enabled             = contains(var.workloads, "ebs")
  clumio_iam_role_tags       = merge({ Vendor = "Clumio" }, var.role_tags)
  permissions_boundary_arn   = var.permissions_boundary_arn
  clumio_pass_role_deny_list = var.pass_role_deny_list
}
EOF

sed -i.bak "s/\"MODULE_VERSION\"/\"$MODULE_VERSION\"/" "$WORK/main.tf" && rm "$WORK/main.tf.bak"
echo "Previewing Clumio's IAM with the settings in $(cd "$CONNECT" && pwd)/terraform.tfvars (module $MODULE_VERSION)..."
( cd "$WORK" && terraform init -input=false -no-color > init.log 2>&1 ) || { cat "$WORK/init.log"; fail "terraform init"; }
( cd "$WORK" && terraform plan -input=false -no-color -out=plan.bin > plan.log 2>&1 ) \
  || { cat "$WORK/plan.log"; fail "terraform plan: see the error above (\"account ID not allowed\": log in to account_id)"; }
( cd "$WORK" && terraform show -json plan.bin > plan.json )
REGION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["variables"]["region"]["value"])' "$WORK/plan.json")"
OUT="$(pwd)/clumio-iam-preview-$REGION-$(date -u +%Y%m%dT%H%M%SZ)"

# --- Plan -> review pack, then make sure nothing sensitive is in it -------------
mkdir -p "$OUT/policies"
python3 "$HERE/extract.py" "$WORK/plan.json" "$OUT" "$ACCOUNT" "$REGION" "$WORK"

# --- Can the deploy role do all of it? Ask the IAM policy simulator. -----
# It evaluates the identity's policies, permission boundaries and SCPs (not resource control
# policies), with the request's Region, tags and boundary as context. It needs
# iam:SimulatePrincipalPolicy. One named result: READY, BLOCKED, CANNOT CHECK.
check_identity() {
  local caller principal denied="" actions arn context results
  caller="$(aws sts get-caller-identity --query Arn --output text)"
  if [ -n "$AS_ARN" ]; then
    principal="$AS_ARN"
  elif [[ "$caller" == *":root" ]]; then
    echo "CANNOT CHECK: you are the account root user, which can do all of it (the simulator can't test root)."; return
  elif [[ "$caller" == *":assumed-role/"* ]]; then   # SSO or assumed role: the simulator needs the role's IAM ARN
    local role_name="${caller#*:assumed-role/}"; role_name="${role_name%%/*}"
    principal="$(aws iam get-role --role-name "$role_name" --query Role.Arn --output text 2>/dev/null)" \
      || { echo "CANNOT CHECK: can't read your role ($role_name) with iam:GetRole. Ask security to run: ./preview.sh --as <deploy role ARN>"; return; }
  else
    principal="$caller"
  fi
  local line
  while IFS= read -r line; do
    # Unmask the whole line: the ARN and its context (iam:PolicyARN) must name the real account.
    line="${line//<ACCOUNT_ID>/$ACCOUNT}"; line="${line//<CLUMIO_TOKEN>/PREVIEWCLUMIOTOKEN}"
    IFS=$'\t' read -r actions arn context <<< "$line"
    # shellcheck disable=SC2086  # actions is a space-separated list on purpose
    results="$(aws iam simulate-principal-policy --policy-source-arn "$principal" --action-names $actions \
      --resource-arns "$arn" --context-entries "$context" \
      --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text 2>&1)" \
      || { echo "CANNOT CHECK: the IAM simulator refused (${results##*: }). It needs iam:SimulatePrincipalPolicy on $principal."; return; }
    denied+="$(awk -v r="$arn" '$2 != "allowed" { printf "  %-14s %-34s %s\n", $2, $1, r }' <<< "$results")"$'\n'
  done < "$WORK/deploy-check.tsv"
  denied="$(grep -v '^$' <<< "$denied" || true)"
  if [ -z "$denied" ]; then
    echo "READY: $principal may do every action above."
  else
    echo "BLOCKED: $principal is missing these (implicitDeny: not granted; explicitDeny: denied by a policy or SCP):"
    echo "$denied"
    echo "Fix: in policies/deploy-role-policy.json replace <ACCOUNT_ID> with your account ID, grant it, then run this again."
  fi
}
echo
echo "Can the deploy role do it?"
CHECK="$(check_identity)"; CHECK="${CHECK//$ACCOUNT/<ACCOUNT_ID>}"   # ARNs and AWS error text carry the account ID
echo "$CHECK" | sed 's/^/  /'
printf '\n## Can the deploy role do it?\n\n```\n%s\n```\n' "$CHECK" >> "$OUT/summary.md"

grep -rq "$ACCOUNT" "$OUT" && fail "account ID found unmasked in the output; nothing written"
FINISHED=1
echo
echo "Next: give this folder to your security team (account ID masked):"
echo "  $OUT/summary.md      the full picture, same headings as above"
echo "  $OUT/policies/       every policy as JSON, ready to review or create"
