/// A mismatch between a plan and its copy. The guide is still built, with empty text where copy is missing, so the
/// caller decides whether to retry the writer or keep the draft.
public enum AssemblyProblem: Hashable, Sendable {
    /// The plan has this item, and the copy does not.
    case missingCopy(CopyTarget)
    /// The copy has this item, and the plan does not.
    case extraCopy(CopyTarget)
    /// The copy has this item more than once. The first copy is kept.
    case duplicateCopy(CopyTarget)
}
