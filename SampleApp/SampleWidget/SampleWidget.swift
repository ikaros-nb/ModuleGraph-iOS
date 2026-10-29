import Core
import SwiftUI
import WidgetKit

// A target with classic groups (no Xcode 16 folder): its sources come from the Sources build phase.
struct PriceView: View {
    var price: Money
    var body: some View { Text(price.amount, format: .currency(code: price.currency)) }
}
