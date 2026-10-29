import Foundation

public struct Money: Sendable, Hashable {
    public var amount: Decimal
    public var currency: String
}
