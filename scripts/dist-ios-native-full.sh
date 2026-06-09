#!/usr/bin/env bash
# =============================================================================
# dist-ios-native-full.sh
#
# Crea el paquete de distribución iOS nativo v0.3.0-beta con XCFrameworks,
# sample app y documentación.
#
# Uso:
#   ./dist-ios-native-full.sh
#
# Output:
#   dist/ios-native-full-v0.3.0-beta.zip
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_ROOT="$REPO_ROOT/ios"
DIST_DIR="$REPO_ROOT/dist"
VERSION="0.3.0-beta"
PACKAGE_NAME="loomit-ios-native-full-${VERSION}"
PACKAGE_DIR="$DIST_DIR/${PACKAGE_NAME}"

echo "============================================"
echo " Loomit iOS Native Distribution Builder"
echo " Version: ${VERSION}"
echo "============================================"

# Limpiar y crear estructura
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"/{XCFrameworks,SampleApp,Docs}

# =============================================================================
# Fase 1: Build XCFrameworks
# =============================================================================
echo ""
echo "── Building XCFrameworks ────────────────────"

# Verificar que existan los XCFrameworks ya buildados o buildarlos
if [ ! -d "$IOS_ROOT/build/unity_xcframeworks" ]; then
    echo "Building XCFrameworks via build_unity_xcframeworks.sh..."
    "$IOS_ROOT/scripts/build_unity_xcframeworks.sh"
fi

# Copiar XCFrameworks al paquete
copy_xcframework() {
    local name="$1"
    local src="$REPO_ROOT/unity-sample-app-unity6/Assets/Plugins/iOS/${name}.xcframework"
    if [ -d "$src" ]; then
        cp -R "$src" "$PACKAGE_DIR/XCFrameworks/"
        echo "  ✓ ${name}.xcframework"
    else
        echo "  ⚠️  ${name}.xcframework not found"
    fi
}

copy_xcframework "LoomitOfferwallCore"
copy_xcframework "LoomitOfferwallAdapterAPI"
copy_xcframework "LoomitOfferwallAdapterMyChips"
copy_xcframework "LoomitOfferwallAdapterTapjoy"
copy_xcframework "LoomitOfferwallDebug"
copy_xcframework "Tapjoy"
copy_xcframework "MyChipsSdk"

# =============================================================================
# Fase 2: Preparar Sample App Nativo
# =============================================================================
echo ""
echo "── Preparing Native Sample App ──────────────"

# Copiar estructura del SampleApp existente
if [ -d "$IOS_ROOT/SampleApp" ]; then
    cp -R "$IOS_ROOT/SampleApp/"* "$PACKAGE_DIR/SampleApp/"
    echo "  ✓ SampleApp files copied"
fi

# Crear README específico para SampleApp
cat > "$PACKAGE_DIR/SampleApp/README.md" <<'EOF'
# Loomit iOS Sample App

## Requisitos
- Xcode 15.0+
- iOS 14.0+
- Swift 5.9+

## Configuración

1. Abrir `SampleApp.xcodeproj` en Xcode
2. Configurar tu `LOOMIT_API_KEY` en `Info.plist`:
   ```xml
   <key>LoomitAPIKey</key>
   <string>YOUR_API_KEY</string>
   ```
3. Seleccionar un simulador o dispositivo
4. Presionar ▶ Run

## Nota Importante

Este proyecto debe abrirse como **aplicación ejecutable** en Xcode, no como librería. Esto es necesario para:
- Ejecutar en simulador físico
- Ver logs en tiempo real
- Probar el ciclo completo del SDK

## Estructura del Proyecto

- `App/` - Código principal de la app
- `SDK/` - Integración del SDK Loomit
- `Resources/` - Assets y configuración

## Troubleshooting

### "Missing package product" errors
Asegúrate de que los XCFrameworks estén correctamente embebidos:
1. Selecciona el target de la app
2. Frameworks, Libraries, and Embedded Content
3. Verifica que todos los .xcframeworks estén en "Embed & Sign"

### No se ven logs
El SDK requiere Xcode UI para ver logs. No uses command-line builds.
EOF

echo "  ✓ SampleApp README created"

# =============================================================================
# Fase 3: Copiar Documentación
# =============================================================================
echo ""
echo "── Copying Documentation ────────────────────"

# Crear estructura de docs
mkdir -p "$PACKAGE_DIR/Docs"

# Copiar o crear guías
if [ -f "$REPO_ROOT/docs/iOS_Loomit_Integration_v0.2.md" ]; then
    cp "$REPO_ROOT/docs/iOS_Loomit_Integration_v0.2.md" "$PACKAGE_DIR/Docs/"
    echo "  ✓ iOS Integration Guide"
fi

if [ -f "$REPO_ROOT/docs/PUBLISHER_SAMPLE_APP_GUIDE_IOS.md" ]; then
    cp "$REPO_ROOT/docs/PUBLISHER_SAMPLE_APP_GUIDE_IOS.md" "$PACKAGE_DIR/Docs/"
    echo "  ✓ Sample App Guide"
fi

# Crear CHANGELOG
cat > "$PACKAGE_DIR/CHANGELOG.md" <<EOF
# Changelog - Loomit iOS SDK v${VERSION}

## v0.3.0-beta

### Features
- Core SDK con offerwall aggregation
- MyChips (maf) provider integrado
- Tapjoy provider integrado con fix de firstResponder crash
- Debug Suite integrada
- Soporte iOS 14.0+

### Dependencies
- Tapjoy SDK (vía SPM)
- MyChips SDK (vía SPM)

### Known Issues
- Tapjoy: Requiere delay de 300ms en cierre (fix implementado)
- Debug Suite: No inicializar SDK automáticamente desde DS

### API
- Swift async/await APIs
- Callback-based alternativa
- Unity bridge disponible
EOF

echo "  ✓ CHANGELOG created"

# =============================================================================
# Fase 4: Crear README Principal
# =============================================================================
echo ""
echo "── Creating Package README ─────────────────"

cat > "$PACKAGE_DIR/README.md" <<EOF
# Loomit Offerwall SDK - iOS Native v${VERSION}

[![Version](https://img.shields.io/badge/version-${VERSION}-blue.svg)](https://loomit.io)
[![Platform](https://img.shields.io/badge/platform-iOS%2014.0+-lightgrey.svg)](https://developer.apple.com/ios)
[![Swift](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)

SDK de offerwall para iOS con soporte multi-provider.

## 📦 Contenido del Paquete

```
loomit-ios-native-full-${VERSION}/
├── XCFrameworks/           # Frameworks precompilados
│   ├── LoomitOfferwallCore.xcframework
│   ├── LoomitOfferwallAdapterAPI.xcframework
│   ├── LoomitOfferwallAdapterMyChips.xcframework
│   ├── LoomitOfferwallAdapterTapjoy.xcframework
│   ├── LoomitOfferwallDebug.xcframework
│   ├── Tapjoy.xcframework
│   └── MyChipsSdk.xcframework
├── SampleApp/              # App de ejemplo ejecutable
│   ├── SampleApp.xcodeproj
│   └── README.md
├── Docs/                   # Documentación
│   ├── iOS_Loomit_Integration_v0.2.md
│   └── PUBLISHER_SAMPLE_APP_GUIDE_IOS.md
├── CHANGELOG.md
└── README.md (este archivo)
```

## 🚀 Quick Start

### 1. Agregar XCFrameworks

Arrastra los .xcframework al proyecto Xcode:
- General → Frameworks, Libraries, and Embedded Content
- Asegúrate de que estén en **"Embed & Sign"**

### 2. Inicializar SDK

```swift
import LoomitOfferwallCore

// En AppDelegate o SceneDelegate
Task {
    try? await OfferwallSdk.shared.configure(
        clientId: "YOUR_CLIENT_ID",
        clientSecret: "YOUR_CLIENT_SECRET"
    )
}
```

### 3. Mostrar Offerwall

```swift
Task {
    let available = try? await OfferwallSdk.shared.checkAvailability()
    if available {
        try? await OfferwallSdk.shared.show(from: viewController)
    }
}
```

## 📚 Documentación

- [Guía de Integración Completa](Docs/iOS_Loomit_Integration_v0.2.md)
- [Guía de Sample App](Docs/PUBLISHER_SAMPLE_APP_GUIDE_IOS.md)
- [CHANGELOG](CHANGELOG.md)

## 🛠 Requisitos

- iOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## 📋 Providers Incluidos

| Provider | Estado | Versión SDK |
|----------|--------|-------------|
| MyChips (maf) | ✅ Estable | Última vía SPM |
| Tapjoy | ✅ Estable | Última vía SPM |

## 🔧 Troubleshooting

### El proyecto no compila
1. Verifica que todos los XCFrameworks estén en "Embed & Sign"
2. Limpia derived data: `Cmd+Shift+K` luego `Cmd+Shift+Option+K`
3. Rebuild: `Cmd+B`

### No se ven logs en consola
- El SDK requiere Xcode UI para logs
- No uses command-line builds para testing
- Asegúrate de que el esquema de build tenga logging habilitado

## 📞 Soporte

- Email: support@loomit.io
- Dashboard: https://dashboard.loomit.io

## 📄 Licencia

Copyright © 2024-2025 Loomit. Todos los derechos reservados.
EOF

echo "  ✓ Package README created"

# =============================================================================
# Fase 5: Crear ZIP de distribución
# =============================================================================
echo ""
echo "── Creating Distribution Archive ──────────"

cd "$DIST_DIR"
rm -f "${PACKAGE_NAME}.zip"
zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME"

echo ""
echo "============================================"
echo " ✅ Distribution package created!"
echo ""
echo " Location: ${DIST_DIR}/${PACKAGE_NAME}.zip"
echo " Size: $(du -h "${PACKAGE_NAME}.zip" | cut -f1)"
echo ""
echo " Contents:"
find "$PACKAGE_NAME" -type f | head -20 | while read f; do
    echo "   - $f"
done
echo "============================================"
