//
//  JSONValue.swift
//  LoomitOfferwallCore
//
//  Representación tipada de un valor JSON arbitrario.
//
//  Diseño:
//  - Enum indirecto (vs `Any`-based AnyCodable): fully `Sendable`, `Equatable`,
//    `Hashable` sin trucos. Tipo-seguro en compile time.
//  - Acepta números como `int(Int64)` o `double(Double)`. Decoder elige el más
//    apropiado: prefiere int si encaja sin pérdida, sino double.
//  - Accesos convenientes (`.stringValue`, `.intValue`, etc.) que devuelven
//    `nil` si el tipo no coincide. Sin coercions implícitas — eso lo hace el
//    caller con métodos explícitos como `.coerceToString()`.
//

import Foundation

/// Valor JSON arbitrario tipado.
///
/// Usar para campos heterogéneos del payload del backend (ej: `credentials`
/// de un provider, `experiment` config). Para campos con tipo conocido,
/// usar tipos concretos.
public indirect enum JSONValue: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }

        // Importante: probar Int64 antes que Double para preservar precisión
        // de enteros grandes (timestamps en ms, IDs).
        if let int = try? container.decode(Int64.self) {
            self = .int(int)
            return
        }

        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
            return
        }

        if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "JSONValue: cannot decode value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:               try container.encodeNil()
        case .bool(let value):    try container.encode(value)
        case .int(let value):     try container.encode(value)
        case .double(let value):  try container.encode(value)
        case .string(let value):  try container.encode(value)
        case .array(let value):   try container.encode(value)
        case .object(let value):  try container.encode(value)
        }
    }
}

// MARK: - Convenient accessors (no coercion)

extension JSONValue {

    /// String exacto (no coerce de números/bool a string).
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Int64 exacto. Si el valor es double sin parte fraccional, lo convierte.
    public var intValue: Int64? {
        switch self {
        case .int(let value):
            return value
        case .double(let value) where value.truncatingRemainder(dividingBy: 1) == 0
                                  && value >= Double(Int64.min)
                                  && value <= Double(Int64.max):
            return Int64(value)
        default:
            return nil
        }
    }

    /// Double exacto (también acepta int convertido).
    public var doubleValue: Double? {
        switch self {
        case .int(let value):    return Double(value)
        case .double(let value): return value
        default:                 return nil
        }
    }

    /// Bool exacto.
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Array de JSONValue.
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Diccionario de JSONValue.
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// `true` si el valor es `null`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - Coercion (explicit, opt-in)

extension JSONValue {

    /// Coerce best-effort a String (acepta números y bools como string).
    /// Para campos del backend donde los publishers a veces mandan "1" en
    /// vez de 1, etc.
    public func coerceToString() -> String? {
        switch self {
        case .null:               return nil
        case .bool(let value):    return value ? "true" : "false"
        case .int(let value):     return String(value)
        case .double(let value):  return String(value)
        case .string(let value):  return value
        case .array, .object:     return nil
        }
    }

    /// Coerce best-effort a Bool. Acepta:
    /// - `bool` → exacto
    /// - `int` → 0 = false, otro = true
    /// - `string` → "true"/"false"/"1"/"0"/"yes"/"no" (case-insensitive)
    public func coerceToBool() -> Bool? {
        switch self {
        case .bool(let value):
            return value
        case .int(let value):
            return value != 0
        case .double(let value):
            return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "1", "yes":  return true
            case "false", "0", "no":  return false
            default:                  return nil
            }
        default:
            return nil
        }
    }
}

// MARK: - ExpressibleBy literals (test ergonomics)

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
