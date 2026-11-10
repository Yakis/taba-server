import Foundation
import PostgresNIO

extension PostgresTripStore {
    public func reviews(_ id: UUID) async throws -> [CopyReviewFlag] {
        let rows = try await client.query("""
            SELECT payload FROM taba_copy_reviews WHERE trip_id = \(id) ORDER BY id
            """, logger: logger)
        var flags: [CopyReviewFlag] = []
        for try await data in rows.decode(Data.self) {
            flags += try JSONDecoder().decode([CopyReviewFlag].self, from: data)
        }
        return flags
    }
}
