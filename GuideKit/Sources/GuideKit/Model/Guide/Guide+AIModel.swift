extension Guide {
    /// The same guide, recording the AI model that wrote it.
    public func recordingAIModel(_ model: String) -> Guide {
        Guide(id: id, version: version, status: status, trip: trip, bookings: bookings, stay: stay,
              places: places, days: days, lists: lists, tasting: tasting, practical: practical, sources: sources,
              hero: hero, notes: notes, openQuestions: openQuestions, aiModel: model)
    }
}
