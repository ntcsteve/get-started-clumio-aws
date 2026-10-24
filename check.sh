#!/usr/bin/env bash
# Checks for changes to this kit itself: run before every commit. Works on copies of each
# step's shipped files (never your .terraform, backend.tf or state). Needs the Terraform
# registry, and a few minutes. Makes no AWS or Clumio calls: the shipped placeholders stop every
# plan, and the tests use mock providers.
#   1. terraform fmt          every .tf and .tfvars is formatted
#   2. terraform validate     each step, with its committed lock file
#   3. shipped placeholders   each step's terraform.tfvars.example stops the plan with a clear message
#   4. step 0 golden tests    extract.py still renders exactly what security reviewed
#   5. module tests           each shared module chooses data, and refuses bad input, as documented (mocks)
#   6. step 1b key checks     a wrong key, or no permanence yes, stops the plan (mock providers)
#   7. workshop               its lab compiles, its core logic passes its tests, and its
#                             Terraform validates with its lock file
set -euo pipefail

cd "$(dirname "$0")"
STEPS="1-connect-clumio 1b-own-key 2-protect-s3 2-protect-rds"
SHIPPED="main.tf variables.tf versions.tf terraform.tfvars.example .terraform.lock.hcl"
FAILED=0
pass() { printf 'PASS  %s\n' "$1"; }
flunk() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
COPIES="$(mktemp -d)"
trap 'rm -rf "$COPIES"' EXIT
cp -R modules "$COPIES/modules"   # the steps call ../modules, so the copies keep the same layout

terraform fmt -recursive -check . > /dev/null && pass "terraform fmt" || flunk "terraform fmt (run: terraform fmt -recursive .)"

for s in $STEPS; do
  mkdir "$COPIES/$s"
  for f in $SHIPPED; do cp "$s/$f" "$COPIES/$s/"; done
  cp "$COPIES/$s/terraform.tfvars.example" "$COPIES/$s/terraform.tfvars"   # as a new user starts
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

for m in clumio-account-iam clumio-rds-protection clumio-s3-protection; do
  (cd "$COPIES/modules/$m" && terraform init -backend=false -input=false > /dev/null 2>&1 && terraform test -no-color > /dev/null 2>&1) \
    && pass "modules/$m: tests" || flunk "modules/$m: terraform test (run it in modules/$m to see why)"
done

cp -R 1b-own-key/tests "$COPIES/1b-own-key/"
(cd "$COPIES/1b-own-key" && terraform test -no-color > /dev/null 2>&1) \
  && pass "1b-own-key: key checks and permanence gate" || flunk "1b-own-key: terraform test (run it in 1b-own-key to see why)"

W=workshops/orders-recovery
mkdir -p "$COPIES/w" && cp -R "$W" "$COPIES/w/"   # the workshop calls ../../modules, copied above
(cd "$COPIES/w/orders-recovery" && python3 -m py_compile lab 2> /dev/null) \
  && pass "$W: lab compiles" || flunk "$W: python syntax"
(cd "$COPIES/w/orders-recovery" && python3 -m unittest discover -s tests > /dev/null 2>&1) \
  && pass "$W: lab tests" || flunk "$W: lab tests (run: python3 -m unittest discover -s tests, in $W)"
(cd "$COPIES/w/orders-recovery" && rm -rf .terraform && terraform init -backend=false -input=false -lockfile=readonly > /dev/null 2>&1 && terraform validate -no-color > /dev/null 2>&1) \
  && pass "$W: terraform validate" || flunk "$W: terraform validate"

[ "$FAILED" = 0 ] && echo "ALL CHECKS PASS" || { echo "CHECKS FAILED"; exit 1; }
