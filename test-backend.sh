#!/usr/bin/env bash
#
# test-backend.sh — Corre el integration test contra backend Loomit.
#
# Uso:
#   ./test-backend.sh TU_API_KEY_AQUI TU_CLIENT_ID_AQUI [TU_APP_ID_AQUI]
#
# Opcionalmente, usa environment test:
#   LOOMIT_ENV=test ./test-backend.sh TU_API_KEY_AQUI TU_CLIENT_ID_AQUI [TU_APP_ID_AQUI]
#
# Nota: app_id es opcional (fallback a bundle ID si no se pasa)

set -euo pipefail

# Validar argumentos
if [ $# -lt 2 ]; then
    echo "❌ Error: faltan argumentos."
    echo ""
    echo "Uso:"
    echo "  ./test-backend.sh TU_API_KEY_AQUI TU_CLIENT_ID_AQUI [TU_APP_ID_AQUI]"
    echo ""
    echo "Opcionalmente, usa environment test:"
    echo "  LOOMIT_ENV=test ./test-backend.sh TU_API_KEY_AQUI TU_CLIENT_ID_AQUI [TU_APP_ID_AQUI]"
    echo ""
    echo "Nota: app_id es opcional (fallback a bundle ID si no se pasa)"
    exit 1
fi

API_KEY="$1"
CLIENT_ID="$2"
APP_ID="${3:-}"  # opcional, tercer argumento
ENV="${LOOMIT_ENV:-live}"  # default live

# Validar Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: xcodebuild no encontrado."
    echo "   Necesitás tener Xcode.app instalado (no solo Command Line Tools)."
    echo "   Instalalo desde App Store y luego:"
    echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# Validar que estamos en el directorio correcto
if [ ! -d "LoomitOfferwallCore" ]; then
    echo "❌ Error: este script debe correrse desde el directorio ios/"
    echo "   Ejecutalo así:"
    echo "   cd ios"
    echo "   ./test-backend.sh TU_API_KEY"
    exit 1
fi

# Cambiar al directorio del package para xcodebuild
cd LoomitOfferwallCore

echo "🧪 Integration test contra backend Loomit"
echo "   Environment: $ENV"
echo "   API Key:     ${API_KEY:0:8}... (truncado)"
echo "   Client ID:   ${CLIENT_ID:0:8}... (truncado)"
if [ -n "$APP_ID" ]; then
    echo "   App ID:      ${APP_ID:0:8}... (truncado)"
else
    echo "   App ID:      (usará bundle ID como fallback)"
fi
echo ""

# Crear archivo temporal con credenciales (xcodebuild no pasa vars de entorno correctamente)
# Usar el mismo directorio que FileManager.default.temporaryDirectory en iOS
CREDENTIALS_FILE="$HOME/Library/Caches/.loomit_test_credentials"
mkdir -p "$HOME/Library/Caches"
cat > "$CREDENTIALS_FILE" <<EOF
{
  "API_KEY": "$API_KEY",
  "CLIENT_ID": "$CLIENT_ID",
  "ENV": "$ENV"
EOF

if [ -n "$APP_ID" ]; then
    echo "  ,\"APP_ID\": \"$APP_ID\"" >> "$CREDENTIALS_FILE"
fi

cat >> "$CREDENTIALS_FILE" <<EOF
}
EOF

# Correr el test
xcodebuild test \
    -scheme LoomitOfferwallCore \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:LoomitOfferwallCoreTests/BackendIntegrationTests 2>&1 | tee /tmp/loomit-test.log

# Limpiar
rm -f "$CREDENTIALS_FILE"

# Verificar resultado
if grep -q "** TEST FAILED **" /tmp/loomit-test.log; then
    echo ""
    echo "❌ Test falló. Revisá el log arriba."
    echo ""
    echo "Si el error es 'backend_http_error 401', tu API key o client ID son inválidos."
    echo "Si es 'backend_http_error 5xx', el backend está caído."
    exit 1
fi

if grep -q "Test skipped - Set LOOMIT_API_KEY env var" /tmp/loomit-test.log; then
    echo ""
    echo "❌ Test fue skipped — no se pasó la API key correctamente."
    exit 1
fi

echo ""
echo "✅ Test pasó. Revisá el output arriba para ver tu xifa, fingerprint y config response."
