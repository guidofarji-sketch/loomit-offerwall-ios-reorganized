#!/bin/bash
# Genera proyecto Xcode para la Sample App desde Package.swift

set -e

echo "Generando proyecto Xcode para LoomitOfferwallSampleApp..."

# Generar proyecto con swift package
swift package generate-xcodeproj --xcconfig-overrides ios.xcconfig 2>/dev/null || {
    echo "Nota: generate-xcodeproj está deprecado en Swift 5.8+"
    echo "Usar 'xcodebuild -scheme LoomitOfferwallSampleApp' directamente"
}

echo "Listo. Abrir LoomitOfferwallSampleApp.xcodeproj en Xcode"
