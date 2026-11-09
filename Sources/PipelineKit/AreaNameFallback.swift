import Foundation
import GuideKit
import SourcesKit

/// A failed reverse lookup leaves that candidate unnamed; other candidates still vote for the cluster.
/// When no lookup succeeds, the destination name is used as a readable fallback.
public enum AreaNameFallback {
    public static func cluster(
        _ candidates: [AreaCandidate], destination: String,
        clusterer: AreaClusterer = AreaClusterer(),
        resolve: @Sendable (Coordinate) async throws -> String?
    ) async throws -> Areas {
        let areas = try await clusterer.cluster(candidates, resolveAreaName: { coordinate in
            do {
                return try await resolve(coordinate)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                return nil
            }
        })
        try Task.checkCancellation()
        let clusters = areas.clusters.map { cluster in
            AreaCluster(id: cluster.id, name: cluster.name ?? destination,
                        candidateIDs: cluster.candidateIDs, centre: cluster.centre)
        }
        return Areas(clusters: clusters, walks: areas.walks)
    }
}
