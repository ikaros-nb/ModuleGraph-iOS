import Testing
@testable import Core

@Test func moneyKeepsItsCurrency() {
    #expect(Money(amount: 3, currency: "EUR").currency == "EUR")
}
