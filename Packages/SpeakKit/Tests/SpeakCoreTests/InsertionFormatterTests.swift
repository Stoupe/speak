import Testing
@testable import SpeakCore

@Suite struct InsertionFormatterTests {
    func format(_ text: String, before: String?, after: Character? = nil, keep: [String] = []) -> String {
        InsertionFormatter.format(text, before: before, after: after, keepCapitalized: keep)
    }

    @Test func unknownContextLeavesTextAlone() {
        #expect(format("Hey there.", before: nil) == "Hey there.")
        #expect(format("Hey there.", before: "") == "Hey there.")
    }

    @Test func newSentenceKeepsCapitalAndAddsSpace() {
        #expect(format("Hey there.", before: "done.") == " Hey there.")
        #expect(format("Hey there.", before: "done. ") == "Hey there.")
        #expect(format("Hey there.", before: "done?\n") == "Hey there.")
    }

    @Test func continuingSentenceLowercases() {
        #expect(format("Then we ship it.", before: "and") == " then we ship it.")
        #expect(format("Then we ship it.", before: "first, ") == "then we ship it.")
    }

    @Test func continuingSentenceKeepsProperWords() {
        #expect(format("I think so.", before: "and") == " I think so.")
        #expect(format("I'm in.", before: "and") == " I'm in.")
        #expect(format("API keys rotate.", before: "and") == " API keys rotate.")
        #expect(format("iPhone sales.", before: "and") == " iPhone sales.")
        #expect(format("Thursday works.", before: "maybe") == " Thursday works.")
        #expect(format("Speak is great.", before: "and", keep: ["Speak"]) == " Speak is great.")
    }

    @Test func continuingSentenceKeepsNames() {
        #expect(format("Sarah said yes.", before: "and") == " Sarah said yes.")
    }

    @Test func insertingBeforeMoreTextDropsFullStop() {
        #expect(format("Quick", before: "the ", after: "b") == "quick ")
        #expect(format("Really quick.", before: "the ", after: "b") == "really quick ")
        #expect(format("Is it?", before: nil, after: "b") == "Is it? ")
        #expect(format("End.", before: "the ", after: " ") == "end.")
    }
}
