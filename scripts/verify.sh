#!/usr/bin/env bash
#
# verify.sh — Build + test de todos los packages SPM iOS.
#
# Uso:
#   ./scripts/verify.sh                 # iPhone 17 (default)
#   SIM_NAME="iPhone 15" ./scripts/verify.sh
#
# Output:
#   - Logs por package en build_logs/<package>.log
#   - Exit code 0 si todo pasa, 1 si algo falla
#

set -euo pipefail

SIM_NAME="${SIM_NAME:-iPhone 17}"
DESTINATION="platform=iOS Simulator,name=${SIM_NAME}"

# Resolver path absoluto al directorio ios/ (raíz del workspace iOS)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_DIR="${IOS_ROOT}/build_logs"
mkdir -p "${LOG_DIR}"

# Lista de packages en orden de dependencia (de menos a más dependencias).
# Cuando se agreguen módulos nuevos, agregarlos acá en orden topológico.
PACKAGES=(
    "LoomitOfferwallAdapterAPI"
    "LoomitOfferwallCore"
    "LoomitOfferwallDebug"
)

echo "==> verify.sh"
echo "    Simulator:  ${SIM_NAME}"
echo "    iOS root:   ${IOS_ROOT}"
echo "    Packages:   ${PACKAGES[*]}"
echo ""

FAILED=()

for pkg in "${PACKAGES[@]}"; do
    pkg_dir="${IOS_ROOT}/${pkg}"

    if [[ ! -d "${pkg_dir}" ]]; then
        echo "  [SKIP] ${pkg} (directory not found)"
        continue
    fi

    log="${LOG_DIR}/${pkg}.log"
    printf "  [TEST] %-35s ... " "${pkg}"

    if (cd "${pkg_dir}" && xcodebuild test \
            -scheme "${pkg}" \
            -destination "${DESTINATION}" \
            -derivedDataPath "${IOS_ROOT}/build/${pkg}") \
            > "${log}" 2>&1
    then
        echo "ok"
    else
        echo "FAIL (see ${log})"
        FAILED+=("${pkg}")
    fi
done

echo ""

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "==> FAIL: ${#FAILED[@]} package(s) failed: ${FAILED[*]}"
    exit 1
fi

echo "==> OK: all ${#PACKAGES[@]} package(s) passed."
