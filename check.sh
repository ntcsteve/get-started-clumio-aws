#!/usr/bin/env bash
# Checks for changes to this kit itself: run before every commit. Works on copies of each
# step's shipped files (never your .terraform, backend.tf or state). Needs the Terraform
# registry; makes no AWS or Clumio calls, because the shipped placeholders stop every plan.
#   1. terraform fmt          every .tf and .tfvars is formatted
#   2. terraform validate     each step, with its committed lock file
#   3. shipped placeholders   each step's terraform.tfvars stops the plan with a clear message
#   4. step 0 golden tests    extract.py still renders exactly what security reviewed
set -euo pipefail

cd "$(dirname "$0")"
STEPS="1-connect-clumio 2-protect-s3 2-protect-rds"
SHIPPED="main.tf variables.tf versions.tf terraform.tfvars .terraform.lock.hcl"
FAILED=0
pass() { printf 'PASS  %s\n' "$1"; }
flunk() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
COPIES="$(mktemp -d)"
trap 'rm -rf "$COPIES"' EXIT

terraform fmt -recursive -check . > /dev/null && pass "terraform fmt" || flunk "terraform fmt (run: terraform fmt -recursive .)"

for s in $STEPS; do
  mkdir "$COPIES/$s"
  for f in $SHIPPED; do cp "$s/$f" "$COPIES/$s/"; done
  if ! (cd "$COPIES/$s" && terraform init -backend=false -input=false -lockfile=readonly > /dev/null 2>&1); then
    flunk "$s: terraform init (lock file out of date?)"; continue
  fi
  (cd "$COPIES/$s" && terraform validate -no-color > /dev/null 2>&1) && pass "$s: terraform validate" || flunk "$s: terraform validate"
  # As shipped, the placeholders must stop the plan before anything else happens.
  out="$(cd "$COPIES/$s" && terraform plan -input=false -no-color 2>&1 || true)"
  grep -q "Set account_id in terraform.tfvars" <<< "$out" && pass "$s: placeholders stop the plan" \
    || flunk "$s: placeholders did not stop the plan"
done

0-iam-preview/test/test.sh > /dev/null 2>&1 && pass "0-iam-preview golden tests" || flunk "0-iam-preview golden tests (run 0-iam-preview/test/test.sh to see the diff)"

[ "$FAILED" = 0 ] && echo "ALL CHECKS PASS" || { echo "CHECKS FAILED"; exit 1; }
