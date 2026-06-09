# Loomit Offerwall SDK — iOS v0.3.0-beta

> **Status**: Distribution Ready — v0.3.0-beta
> **Distribución**: [Ver paquetes](#distribución)
> **Plan maestro**: [`../iOS_OFFERWALL_PLAN.md`](../iOS_OFFERWALL_PLAN.md)
> **Arquitectura (north star)**: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)

Implementación nativa Swift del Loomit Offerwall SDK, paridad arquitectónica con la versión Android (`/offerwall-core`, `/offerwall-adapter-api`, etc.).

---

## Stack técnico

| Aspecto | Decisión |
|---|---|
| Lenguaje | Swift 5.9+ |
| Deployment target | iOS 14.0 |
| Build system | Swift Package Manager (SPM) |
| Concurrencia | Swift Concurrency (actors + async/await) |
| Persistencia (XIFA, config cache) | `UserDefaults` |
| Persistencia (event queue) | SQLite via `GRDB.swift` |
| Networking | `URLSession` + async/await |
| Crypto (SHA-256) | `CryptoKit` (built-in) |
| Identifiers | `IDFV` para fingerprint, UUID propio (XIFA) |
| Unity bridge | `@objc` Swift + ObjC bridging para `UnitySendMessage` |

---

## Estructura de módulos

```
ios/
├── Package.swift                       # SPM workspace
├── LoomitOfferwallAdapterAPI/          # Protocolos + tipos compartidos (sin deps)
├── LoomitOfferwallCore/                # Espina dorsal del SDK
├── LoomitOfferwallAdapterMyChips/      # Adapter MAF (PoC #1)
├── LoomitOfferwallAdapterTapjoy/       # Adapter Tapjoy (PoC #2)
├── LoomitOfferwallDebug/               # Debug suite (UI + red debug, opcional)
├── LoomitNativeAds/                    # Native ads (opcional, independiente)
├── LoomitAntifraud/                    # Antifraud (opcional, independiente)
├── ios-sample-app/                     # Sample-app SwiftUI
├── unity-ios-plugin/                   # Plugin nativo iOS para Unity
└── scripts/
    ├── dist-ios-frameworks.sh          # Empaqueta XCFrameworks
    ├── build_unity_xcframeworks.sh      # Build para Unity
    └── verify.sh                        # Validación de packages
```

### Reglas de dependencias (mismas que Android)

| Desde | Puede importar | NO puede importar |
|---|---|---|
| `LoomitOfferwallCore` | `LoomitOfferwallAdapterAPI`, libs estándar | adapters concretos, debug, native-ads, antifraud |
| Adapter concreto | `LoomitOfferwallAdapterAPI`, SDK del provider | core, otros adapters, debug |
| `LoomitOfferwallDebug` | `LoomitOfferwallCore` (lectura via reflection) | adapters, providers concretos |
| `LoomitNativeAds`, `LoomitAntifraud` | (independientes) | core, adapters |

### Reflection boundary

Los módulos opcionales (`Debug`, `NativeAds`, `Antifraud`) se cargan desde core via `NSClassFromString`. Core compila/corre sin ellos.

---

## Invariantes (ver `../ARCHITECTURE.md` §2)

1. **Single-path listener**: UX callbacks (`onShow`, `onClose`, `onRewarded`, etc.) solo via listener global de `OfferwallSdk.setListener(...)`.
2. **Identifiers**: `xifa` único install identifier (UUID en `UserDefaults`). `device_fingerprint` v1 = `SHA-256(IDFV + ":" + bundleIdentifier)`. Cascada `currentUserId ?? publisherUserId ?? xifa` para `user_id` en eventos.
3. **Reflection boundary**: core no importa módulos opcionales.
4. **Backend-driven config**: cero credenciales hardcoded de providers.
5. **Reutilización**: no crear sistemas paralelos de logging/eventos/resiliencia.
6. **Multi-plataforma**: cada API pública = Swift API + Unity bridge + sample-app iOS + sample-app Unity.

---

## Build local

`swift build` por sí solo NO funciona para los módulos que importan `UIKit` (compila para macOS). Usar `xcodebuild` con destination iOS Simulator:

```bash
# Validar TODOS los packages (build + test)
./scripts/verify.sh

# Cambiar simulator
SIM_NAME="iPhone 15" ./scripts/verify.sh

# Validar un package específico
cd LoomitOfferwallCore
xcodebuild test -scheme LoomitOfferwallCore \
    -destination 'platform=iOS Simulator,name=iPhone 17'
```

Pre-requisitos:
- Xcode.app instalado (no solo Command Line Tools).
- `xcode-select -p` debe apuntar a `/Applications/Xcode.app/Contents/Developer`.
- Simulators iOS disponibles: `xcrun simctl list devices available | grep iPhone`.

---

## Estado actual

- [x] **ETAPA 0** — Fundamentos (scaffold, SPM, modelos wire, JSONValue) — 27 tests
- [x] **ETAPA 1** — `OfferwallSdk` actor + listener global single-path — incluido
- [x] **ETAPA 2** — Identifiers (XIFA, IDFV, fingerprint v1) — incluido
- [x] **ETAPA 3** — Distribución — Paquetes listos para publishers

---

## Distribución

### Paquetes Disponibles

| Paquete | Descripción | Ubicación |
|---------|-------------|-----------|
| **iOS Native Full** | XCFrameworks + Sample App | `dist/loomit-ios-native-full-v0.3.0-beta.zip` |
| **Unity Complete** | Android + iOS unificado | `dist/loomit-unity-complete-v0.3.0-beta.zip` |

### Contenido iOS Native Full

```
loomit-ios-native-full-v0.3.0-beta/
├── XCFrameworks/
│   ├── LoomitOfferwallCore.xcframework
│   ├── LoomitOfferwallAdapterAPI.xcframework
│   ├── LoomitOfferwallAdapterMyChips.xcframework
│   ├── LoomitOfferwallAdapterTapjoy.xcframework
│   ├── LoomitOfferwallDebug.xcframework
│   ├── Tapjoy.xcframework
│   └── MyChipsSdk.xcframework
├── SampleApp/
│   └── SampleApp.xcodeproj (ejecutable)
└── Docs/
    └── iOS_Loomit_Integration_v0.2.md
```

### Quick Start para Publishers

1. **Descargar** el paquete correspondiente
2. **Agregar XCFrameworks** al proyecto Xcode (Embed & Sign)
3. **Configurar** credenciales en `Info.plist`
4. **Ejecutar** el SampleApp para verificar integración

### Documentación

- [Guía de Integración iOS](../docs/iOS_Loomit_Integration_v0.2.md)
- [Unity iOS Supplement](../docs/Unity_iOS_Integration_Supplement.md)
- [Architecture](../UNITY_IOS_BRIDGE_ARCHITECTURE.md)

---

## Providers Soportados

| Provider | Versión SDK | Estado |
|----------|-------------|--------|
| MyChips (maf) | Última vía SPM | ✅ Estable |
| Tapjoy | Última vía SPM | ✅ Estable (fix crash incluido) |

---

## Scripts de Distribución

```bash
# Build XCFrameworks para distribución
./scripts/build_unity_xcframeworks.sh

# Crear paquete iOS Native (desde root del repo)
./dist-ios-native-full.sh

# Crear paquete Unity Complete (desde root del repo)
./dist-unity-complete.sh
```
- [x] **ETAPA 3** — `AdapterRegistry` con discovery explícito — incluido
- [x] **ETAPA 4** — Backend client HTTP + RetryingBackendClient — incluido
- [ ] **ETAPA 4-bis** — Circuit breaker + ConfigCache 3-tier (hardening)
- [ ] **ETAPA 5** — Event pipeline (manager + queue + retry pusher)
- [ ] **ETAPA 6** — Production logger
- [ ] **ETAPA 6.5** — Debug suite
- [ ] **ETAPA 7** — Adapter MAF/MyChips
- [ ] **ETAPA 7.5** — Adapter Tapjoy
- [ ] ETAPA 8+ — sample apps, Unity bridge, distribución

### Resumen actual

| Aspecto | Resultado |
|---|---|
| Packages SPM | 2 (`LoomitOfferwallAdapterAPI`, `LoomitOfferwallCore`) |
| Unit tests | **67/67 passing** + 2 integration (skipped sin env var) |
| Build target | iOS 14.0+, arm64 simulator |
| Dependencias externas | 0 (solo Foundation + UIKit + CryptoKit) |
| Sendable strict | Sí — `JSONValue` enum-based, sin `@unchecked` excepto donde justificado |
| Single-path listener | ✅ enforced via `ListenerDispatcher` centralizado |
| userId cascade | ✅ `currentUserId ?? publisherUserId ?? xifa` |
| Fingerprint v1 | ✅ `SHA-256(idfv_lowercased + ":" + bundleId)` con vector conocido |

---

## 🟢 Punto de prueba: Integration test contra backend real

Ahora podés validar la cadena completa **identifiers → request → response** contra tu backend Loomit real, sin necesidad de UI todavía.

### Requisitos

- Una API key de Loomit válida.
- Decidí qué environment querés: `live` (default) o `test`.

### Comando

```bash
LOOMIT_API_KEY="tu-api-key-aca" \
LOOMIT_ENV=test \
xcodebuild test \
    -scheme LoomitOfferwallCore \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:LoomitOfferwallCoreTests/BackendIntegrationTests
```

(omitir `LOOMIT_ENV` para usar `live`)

### Qué hace

1. Crea un `OfferwallSdk` con `IdentifierStore` aislado (no contamina UD del simulator).
2. Setea API key + environment.
3. Imprime `xifa`, `device_fingerprint`, endpoint usado.
4. Hace `fetchConfig()` — POST real a `/get-app-config`.
5. Imprime un resumen del response: segment, waterfall (con providers + priorities + credentials keys), ad_space overrides, logging config.
6. Valida que `state` quedó en `.ready`.
7. Hace un segundo test con API key inválida y valida que devuelve 4xx (no retry).

### Output esperado (ejemplo)

```
[Integration] xifa:        a1b2c3d4-...
[Integration] fingerprint: 3f0e7c4a8b2d6...
[Integration] env:         test
[Integration] endpoint:    https://ephrjxiqtbikewfjeabv.supabase.co/functions/v1/get-app-config

[Integration] ---- ConfigResponse summary ----
[Integration] segment:           default
[Integration] debuggingStatus:   false
[Integration] configurations:    0
[Integration] default_waterfall: 2 provider(s)
[Integration]   [0] tapjoy prio=1 active=true creds_keys=["placement_id", "sdk_key"]
[Integration]   [1] mychips prio=2 active=true creds_keys=["app_id", ...]
[Integration] logging: enabled=true categories=["events", "network"]
[Integration] ---- end summary ----
```

### Si falla

- **`backend_http_error` con 401**: API key inválida.
- **`backend_http_error` con 5xx**: backend caído / error transient. RetryPolicy reintentó pero igual falló.
- **`backend_decoding_error`**: el wire schema cambió en backend y nuestro decoder no se adapta. Avísame y ajusto los modelos.
- **`backend_unreachable`**: red. Verificá conectividad del Mac/simulator.
