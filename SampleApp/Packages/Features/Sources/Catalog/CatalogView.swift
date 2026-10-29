import Collections
import Core
import SwiftUI

public struct CatalogView: View {
    var products: OrderedDictionary<Product.ID, Product>

    public var body: some View {
        List(products.values) { Text($0.name) }
    }
}
