import Analytics // Imported but not declared: reached through Catalog.
import Catalog
import Checkout
import SwiftUI
import Kingfisher // Declared nowhere: reported as an unresolved import.

@main
struct SampleApp: App {
    var body: some Scene {
        WindowGroup { Text("SampleApp") }
    }
}
