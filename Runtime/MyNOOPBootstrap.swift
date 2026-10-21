#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI

// Seed bundle language before SwiftUI creates the app and its stored properties.
@main @MainActor enum MyNOOPBootstrap {
    static func main() {
        PersonalDefaults.seed()
        StrandiOSApp.main()
    }
}
#endif
