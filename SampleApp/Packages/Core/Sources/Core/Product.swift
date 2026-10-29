import Foundation

public struct Product: Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var price: Money
}
