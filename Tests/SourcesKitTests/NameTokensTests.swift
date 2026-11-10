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

    @Test func aSharedPlaceTypeWordAloneIsNotTheSamePlace() {
        // "Steps" is shared, but the wanted name has "Vennel" too, and that is a different flight of steps.
        #expect(NameTokens.nameSimilarity("The Vennel Steps", "Waverley Steps") == 0)
    }

    @Test func aNameThatAddsWordsToTheSamePlaceStillMatches() {
        #expect(NameTokens.nameSimilarity("Calton Hill", "Calton Hill Observatory") >= NameTokens.acceptableSimilarity)
        #expect(NameTokens.nameSimilarity("Stockbridge Market", "Stockbridge Sunday Market")
            >= NameTokens.acceptableSimilarity)
    }

    @Test func aWantedNameOfPlaceTypeWordsKeepsItsScore() {
        // "Steps" against "Waverley Steps": recall 1, precision one half, F1 two thirds, as before.
        let score = NameTokens.nameSimilarity("Steps", "Waverley Steps")
        #expect(abs(score - 2.0 / 3.0) < 0.0001)
    }

    @Test func foodAndDrinkWordsAloneDoNotMakeTwoPlacesTheSame() {
        // "Ale" and "House" are shared, but "Ale" names a kind of pub, not which one, so only "House" is left.
        #expect(NameTokens.significant("The Ale House") == ["house"])
        #expect(NameTokens.nameSimilarity("Smithies Ale House", "The Ale House") == 0)
    }

    @Test func aNameOfOnlyFoodWordsKeepsAllItsWords() {
        #expect(NameTokens.significant("The Ale") == ["the", "ale"])
    }

    @Test func theCorrectMatchesStillReachTheAcceptableSimilarity() {
        let pairs: [(wanted: String, found: String)] = [
            ("The Vennel", "The Vennel Viewpoint Edinburgh Castle"),
            ("Calton Hill", "Calton Hill Observatory"),
            ("Stockbridge Market", "Stockbridge Sunday Market"),
            ("The Café Royal Circle Bar", "Cafe Royal"),
            ("Edinburgh's Christmas Market, East Princes Street Gardens", "East Princes Street Gardens"),
            ("The Stockbridge Tap", "The Stockbridge Tap"),
            ("Sandy Bell's", "Sandy Bell's"),
            ("Clark's Bar", "Clark's Bar")
        ]
        for pair in pairs {
            let score = NameTokens.nameSimilarity(pair.wanted, pair.found, cityName: "Edinburgh")
            #expect(score >= NameTokens.acceptableSimilarity, "\(pair.wanted) against \(pair.found) scored \(score)")
        }
    }
}
