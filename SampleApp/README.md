# Loomit Offerwall Sample App (iOS)

Aplicación de ejemplo para probar el SDK LoomitOfferwall en iOS usando CocoaPods.

## Características

- **Initialize SDK**: Configura el SDK con credenciales de staging
- **Show Offerwall**: Muestra el offerwall cuando está disponible
- **Check Status**: Verifica el estado de inicialización y disponibilidad
- **Debug Panel**: Panel de debug en tiempo real para ver eventos del SDK
- **Event Console**: Logs en tiempo real de todos los eventos trackeados

## Credenciales (Staging)

```swift
API Key: lmt_b1debf8669027a925c0e60cf3e0377e206c47e8c8dba3897
Client ID: cl_417b8
App ID: ap_41d5f8d28c
```

## Estructura

```
Sources/
├── AppDelegate.swift           # Entry point
├── MainViewController.swift    # UI principal con botones de acción
├── DebugViewController.swift   # Debug panel con lista de eventos
└── (otros archivos de UI)
```

## Dependencias (CocoaPods Subspecs)

El Podfile usa **subspecs** para selección modular de adapters:

```ruby
pod 'LoomitOfferwall', :subspecs => ['Core', 'AdapterAPI', 'AdapterMyChips', 'AdapterTapjoy', 'Debug']
```

| Subspec | Contenido |
|---------|-----------|
| `Core` | SDK principal (requerido) |
| `AdapterAPI` | Interfaz de adapters (requerido por adapters) |
| `AdapterMyChips` | Adapter de MyChips + vendored xcframework |
| `AdapterTapjoy` | Adapter de Tapjoy + TapjoySDK (~> 14.7) |
| `Debug` | Debug suite para eventos en tiempo real |

**Nota**: Si querés excluir un provider, sacalo de la lista `:subspecs`.

## Instalación paso a paso

### 1. Instalar CocoaPods (si no está instalado)

```bash
sudo gem install cocoapods
```

### 2. Instalar dependencias

```bash
cd /Users/guido.farji/Loomit-OW-SDK/ios/SampleApp
rm -rf Pods Podfile.lock
pod install
```

> El `rm -rf Pods Podfile.lock` fuerza una instalación limpia sin caches.

### 3. Abrir el workspace

**IMPORTANTE**: Abrí el `.xcworkspace`, **NUNCA** el `.xcodeproj`:

```bash
open LoomitOfferwallSampleApp.xcworkspace
```

### 4. Seleccionar destino y compilar

1. **Product → Destination** → elegí un simulador iOS (ej: iPhone 17)
2. **Product → Scheme** → `LoomitOfferwallSampleApp`
3. **Run** (Cmd+R)

## Flujo de uso

1. Tap en "1. Inicializar SDK"
2. Esperar a que muestre "✅ Inicializado"
3. Tap en "2. Mostrar Offerwall"
4. Usar "🔍 Abrir Debug Panel" para ver eventos en tiempo real

## Debug Suite

El debug panel muestra:
- Eventos trackeados en tiempo real
- Timestamp de cada evento
- Provider asociado
- Payload completo (tap en evento para ver detalle)

## Notas

- Usa ambiente `.test` para staging
- El SDK requiere iOS 15+
- La sample app incluye MyChipsAdapter y TapjoyAdapter por defecto
- Todas las dependencias se descargan desde el pod repo público

## Troubleshooting

### Error: "Pod not found"

Asegurarse de haber ejecutado `pod install` y abrir el `.xcworkspace` en lugar del `.xcodeproj`.

### Error: "While building for macOS, no library for this platform was found"

1. **Cerrar Xcode completamente**
2. **Borrar Derived Data**: `rm -rf ~/Library/Developer/Xcode/DerivedData/SampleApp-*`
3. **Reabrir LoomitOfferwallSampleApp.xcworkspace**
4. **Product → Destination** → seleccionar "iPhone 17" o "iPhone 17 Air"
5. **Product → Clean Build Folder** (Cmd+Shift+K)
6. **Build** (Cmd+B)

**IMPORTANTE**: Asegurarse de que en el dropdown de destino aparezca el ícono de iPhone (📱) y no la Mac (💻) antes de compilar.

### Debug Panel no muestra eventos

Asegurarse de haber inicializado el SDK primero (botón "1. Inicializar SDK"). El debug collector se conecta durante la inicialización.
