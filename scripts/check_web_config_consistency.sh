#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_DIR"

echo "[1/6] check default hosting target"
grep -q '"public": "build/web-domly"' firebase.json

echo "[2/6] check release hosting targets"
grep -q '"site": "domly-d0f91"' firebase.hosting.multi.json
grep -q '"public": "build/web-domly"' firebase.hosting.multi.json
grep -q '"site": "domly-pro"' firebase.hosting.multi.json
grep -q '"public": "build/web-pro"' firebase.hosting.multi.json
grep -q '"site": "domly-admin-web"' firebase.hosting.admin.json
grep -q '"public": "build/web-admin"' firebase.hosting.admin.json

echo "[3/6] check release helper scripts"
test -f scripts/build_web_domly.sh
test -f scripts/build_web_domly_pro.sh
test -f scripts/build_web_admin.sh
test -f scripts/check_functions_node_version.sh
test -f scripts/install_functions_dependencies.sh
test -f scripts/use_functions_node_env.sh
test -f scripts/check_functions_deploy_access.sh
test -f scripts/deploy_functions.sh
test -f scripts/deploy_all.sh
test -f scripts/prepare_backend_deploy.sh
test -f scripts/deploy_web_all.sh
test -f scripts/verify_release_readiness.sh

echo "[4/6] ensure backend deploy does not publish hosting"
! grep -q 'deploy --only functions,hosting' scripts/deploy_all.sh
grep -q 'deploy --only functions' scripts/deploy_all.sh

echo "[5/6] ensure backend scripts use shared preflight helpers"
grep -q 'check_functions_node_version\.sh' scripts/deploy_functions.sh
grep -q 'check_functions_deploy_access\.sh' scripts/deploy_functions.sh
grep -q 'install_functions_dependencies\.sh' scripts/deploy_functions.sh
grep -q 'check_functions_node_version\.sh' scripts/deploy_all.sh
grep -q 'check_functions_deploy_access\.sh' scripts/deploy_all.sh
grep -q 'install_functions_dependencies\.sh' scripts/deploy_all.sh
grep -q 'check_functions_node_version\.sh' scripts/prepare_backend_deploy.sh
grep -q 'check_functions_deploy_access\.sh' scripts/prepare_backend_deploy.sh
grep -q 'install_functions_dependencies\.sh' scripts/prepare_backend_deploy.sh
grep -q 'check_functions_deploy_access\.sh' scripts/verify_release_readiness.sh

echo "[6/6] ensure deploy_web_all validates artifacts"
grep -q '<title>DOMLY</title>' scripts/deploy_web_all.sh
grep -q '<title>Domly Pro</title>' scripts/deploy_web_all.sh
grep -q '<title>Domly Admin Web</title>' scripts/deploy_web_all.sh

echo "[OK] Release config consistency checks passed"
