import Catalog
import Core
import SwiftUI

public struct CheckoutView: View {
    var total: Money

    public var body: some View {
        Text("\(total.amount)")
    }
}
