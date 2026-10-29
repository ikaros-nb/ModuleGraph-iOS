import Core
import OSLog

public struct Tracker: Sendable {
    public init() {}
    public func viewed(_ product: Product) {
        Logger().info("viewed \(product.name)")
    }
}
