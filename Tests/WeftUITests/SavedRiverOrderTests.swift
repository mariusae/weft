import Testing
@testable import WeftUI

struct SavedRiverOrderTests {
    @Test func placeKeptInFrontmatter() {
        var river = SavedRiver(cards: ["Alpha"])
        river.place = 2.5
        let read = SavedRiver(text: river.text)
        #expect(read.place == 2.5)
        #expect(read.cards == ["Alpha"])
        river.place = 3
        #expect(river.text.contains("place: 3\n"))
    }

    @Test func noPlaceNoLine() {
        #expect(!SavedRiver(cards: ["Alpha"]).text.contains("place"))
    }
}

struct HomeRiverChoiceTests {
    typealias Choice = HomeRiverPicker.Choice

    @Test func nothingTypedHomeFirstThenNone() {
        let choices = HomeRiverPicker.choices(for: "", saved: ["Alpha", "Beta", "Work"], home: "Beta")
        #expect(choices == [.river("Beta"), .river("Alpha"), .river("Work"), .none])
    }

    @Test func typedThoseBeginningWithItFirstThenNew() {
        let choices = HomeRiverPicker.choices(for: "wo", saved: ["Homework", "Work", "Alpha"], home: nil)
        #expect(choices == [.river("Work"), .river("Homework"), .new("wo")])
    }

    @Test func typedNameOfOneNoNew() {
        #expect(HomeRiverPicker.choices(for: "work", saved: ["Work"], home: nil) == [.river("Work")])
    }
}
