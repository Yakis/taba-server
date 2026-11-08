import SourcesKit
import Testing

struct NameTokensTests {
    @Test func foldsCaseDiacriticsAndPunctuation() {
        #expect(NameTokens.significant("Café Lumière!") == ["lumiere"])
    }

    @Test func readsAmpersandAsAnd() {
        // "and" is generic, so "M&S" leaves its two letters.
        #expect(NameTokens.significant("M&S Food Stockbridge") == ["m", "s", "stockbridge"])
    }

    @Test func dropsAPossessiveAndTheCityName() {
        #expect(NameTokens.significant("Edinburgh's Christmas", cityName: "Edinburgh") == ["christmas"])
    }

    @Test func dropsGenericWordsAndKeepsTheRest() {
        #expect(NameTokens.significant("The Abbotsford Bar") == ["abbotsford"])
    }

    @Test func aNameOfGenericWordsKeepsAllItsWords() {
        #expect(NameTokens.significant("The Bar") == ["the", "bar"])
    }

    @Test func eachTokenCountsOnce() {
        #expect(NameTokens.significant("Oink Oink Oink") == ["oink"])
    }

    @Test func identicalTokensGiveSimilarityOne() {
        #expect(NameTokens.nameSimilarity("The Abbotsford", "Abbotsford") == 1)
    }

    @Test func noSharedTokensGiveSimilarityZero() {
        #expect(NameTokens.nameSimilarity("Bow Bar", "Cafe Lumiere") == 0)
    }

    @Test func partialOverlapIsAnF1Score() {
        // Wanted [oink, victoria] against found [victoria]: recall 0.5, precision 1, F1 two thirds.
        let score = NameTokens.nameSimilarity("Oink Victoria Street", "Victoria Street")
        #expect(abs(score - 2.0 / 3.0) < 0.0001)
    }
}
