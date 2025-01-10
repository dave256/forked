import Foundation

public extension ForkedResource {
    
    /// Merges from one fork into the main fork. May perform a 3-way merge.
    /// A `MergeAction` is returned to indicate the type of merge that took place.
    /// After this operation, the main fork may be updated. The version of the other fork will be unchanged.
    /// Note that this may change the commits stored in unrelated forks, in order to preserve common ancestors.
    /// This particular overload handles merges of non-`Mergeable` resources.
    @discardableResult func mergeIntoMain(from fromFork: Fork) throws -> MergeAction {
        try performMergeIntoMain(from: fromFork, mergedContentFunc: mergedContent)
    }
    
    /// Merges from the main fork into another fork. May perform a 3-way merge.
    /// A `MergeAction` is returned to indicate the type of merge that took place.
    /// After this operation, the fork may be updated, with the version of the main fork unchanged.
    /// This particular overload handles merges of non-`Mergeable` resources.
    @discardableResult func mergeFromMain(into toFork: Fork) throws -> MergeAction {
        try performMergeFromMain(into: toFork, mergedContentFunc: mergedContent)
    }
    
    /// Brings main and the other fork to the same version by first merging from
    /// the other fork into main, and then merging from main into the other fork (fast forward).
    /// This particular overload handles merges of  `Mergeable` resources.
    /// To sync up all forks, just pass all forks to this func, including .main. The main fork is ignored
    /// when merging.
    func syncMain(with forks: [Fork]) throws {
        try performSyncMain(with: forks, mergedContentFunc: mergedContent)
    }
    
    /// Merges other forks into main, and then main into the target fork, so it has up-to-date data from all other forks.
    /// You can pass in `.main` if you want to merge all other forks into `.main`.
    func mergeAllForks(into toFork: Fork) throws {
        try performMergeAllForks(into: toFork, mergedContentFunc: mergedContent)
    }
    
    /// Merges all forks so they are all at the same version. This involves merging all forks into the main fork
    /// first, and then merging the main fork into all other forks.
    func syncAllForks() throws {
        try performSyncAllForks(mergedContentFunc: mergedContent)
    }
    
    /// If the Resource is not Mergeable, fallback to last-write-wins approach. Most recent commit is chosen.
    internal func mergedContent(forConflicting commits: ConflictingCommits<ResourceType>, withCommonAncestor ancestorCommit: Commit<ResourceType>) throws -> CommitContent<ResourceType> {
        return commits.dominant.content
    }
    
}

/// These methods handle the special case that the Resource is Mergeable. We need to do that here, so that
/// the compiler can properly choose the appropriate overload.
public extension ForkedResource where RepositoryType.Resource: Mergeable {
    
    /// Merges from one fork into the main fork. May perform a 3-way merge.
    /// A `MergeAction` is returned to indicate the type of merge that took place.
    /// After this operation, the main fork may be updated. The version of the other fork will be unchanged.
    /// Note that this may change the commits stored in unrelated forks, in order to preserve common ancestors.
    /// This particular overload handles merges of `Mergeable` resources.
    @discardableResult func mergeIntoMain(from fromFork: Fork) throws -> MergeAction {
        try performMergeIntoMain(from: fromFork, mergedContentFunc: mergedContent)
    }
    
    /// Merges from the main fork into another fork. May perform a 3-way merge.
    /// A `MergeAction` is returned to indicate the type of merge that took place.
    /// After this operation, the fork may be updated, with the version of the main fork unchanged.
    /// This particular overload handles merges of `Mergeable` resources.
    @discardableResult func mergeFromMain(into toFork: Fork) throws -> MergeAction {
        try performMergeFromMain(into: toFork, mergedContentFunc: mergedContent)
    }
    
    /// Brings main and the other fork to the same version by first merging from
    /// the other fork into main, and then merging from main into the other fork (fast forward).
    /// This particular overload handles merges of  `Mergeable` resources.
    /// To sync up all forks, just pass all forks to this func, including .main. The main fork is ignored
    /// when merging.
    func syncMain(with forks: [Fork]) throws {
        try performSyncMain(with: forks, mergedContentFunc: mergedContent)
    }
    
    /// Merges other forks into main, and then main into the target fork, so it has up-to-date data from all other forks.
    /// You can pass in `.main` if you want to merge all other forks into `.main`.
    /// This particular overload handles merges of  `Mergeable` resources.
    func mergeAllForks(into toFork: Fork) throws {
        try performMergeAllForks(into: toFork, mergedContentFunc: mergedContent)
    }
    
    /// Merges all forks so they are all at the same version. This involves merging all forks into the main fork
    /// first, and then merging the main fork into all other forks.
    /// This particular overload handles merges of  `Mergeable` resources.
    func syncAllForks() throws {
        try performSyncAllForks(mergedContentFunc: mergedContent)
    }
    
    /// For `Mergeable` types, we ask the `Resource` to do the merging itself
    internal func mergedContent(forConflicting commits: ConflictingCommits<ResourceType>, withCommonAncestor ancestorCommit: Commit<ResourceType>) throws -> CommitContent<ResourceType>  {
        switch (commits.dominant.content, commits.subordinate.content, ancestorCommit.content) {
        case (.none, .none, _):
            return .none
        case (.resource, .none, _):
            return commits.dominant.content
        case (.none, .resource, _):
            return commits.subordinate.content
        case (.resource(let r1), .resource(let r2), .none):
            let resource = try r1.salvaging(from: r2)
            return .resource(resource)
        case (.resource(let r1), .resource(let r2), .resource(let ra)):
            let resource = try r1.merged(withSubordinate: r2, commonAncestor: ra)
            return .resource(resource)
        }
    }
}

private extension ForkedResource {
    
    @discardableResult func performMergeIntoMain(from fromFork: Fork, mergedContentFunc: (ConflictingCommits<ResourceType>, Commit<ResourceType>) throws -> CommitContent<ResourceType>) throws -> MergeAction {
        try serialize {
            var change: ForkChange?
            defer {
                if let change {
                    addToChangeStreams(change)
                }
            }
            
            switch (try hasUnmergedCommitsForMain(in: fromFork), try hasUnmergedCommitsInMain(for: fromFork)) {
                case (true, true):
                    let mainCommit = try mostRecentCommit(of: .main)
                    let fromCommit = try mostRecentCommit(of: fromFork)
                    let ancestorCommit = try commonAncestor(of: fromFork)
                    let commits = ConflictingCommits(commits: (mainCommit, fromCommit))
                    let content = try mergedContentFunc(commits, ancestorCommit)
                    let newVersion = try update(.main, with: content)
                    change = ForkChange(fork: .main, version: newVersion, mergingFork: fromFork)
                    try removeAllCommitsExceptMostRecent(in: fromFork) // Fork version is now common ancestor
                    return .resolveConflict
                case (true, false):
                    try addCommonAncestorsToEmptyForks()
                    try repository.copyMostRecentCommit(from: fromFork, to: .main)
                    try removeRedundantCommits(in: .main)
                    try removeAllCommits(in: fromFork)
                    let newVersion = try mostRecentVersion(of: .main)
                    change = ForkChange(fork: .main, version: newVersion, mergingFork: fromFork)
                    return .fastForward
                case (false, true), (false, false):
                    return .none
            }
        }
    }
    
    @discardableResult func performMergeFromMain(into toFork: Fork, mergedContentFunc: (ConflictingCommits<ResourceType>, Commit<ResourceType>) throws -> CommitContent<ResourceType>) throws -> MergeAction {
        try serialize {
            var change: ForkChange?
            defer {
                if let change {
                    addToChangeStreams(change)
                }
            }
            
            switch (try hasUnmergedCommitsForMain(in: toFork), try hasUnmergedCommitsInMain(for: toFork)) {
                case (true, true):
                    let mainCommit = try mostRecentCommit(of: .main)
                    let toCommit = try mostRecentCommit(of: toFork)
                    let ancestorCommit = try commonAncestor(of: toFork)
                    let commits = ConflictingCommits(commits: (mainCommit, toCommit))
                    let content = try mergedContentFunc(commits, ancestorCommit)
                    let newVersion = try update(toFork, with: content)
                    try repository.copyMostRecentCommit(from: .main, to: toFork) // New common ancestor is the main version
                    try removeCommonAncestor(in: toFork) // Remove old common ancestor
                    change = ForkChange(fork: toFork, version: newVersion, mergingFork: .main)
                    return .resolveConflict
                case (false, true):
                    try removeAllCommits(in: toFork)
                    let newVersion = try mostRecentVersion(of: toFork)
                    change = ForkChange(fork: toFork, version: newVersion, mergingFork: .main)
                    return .fastForward
                case (true, false), (false, false):
                    return .none
            }
        }
    }
    
    func performSyncMain(with forks: [Fork], mergedContentFunc: (ConflictingCommits<ResourceType>, Commit<ResourceType>) throws -> CommitContent<ResourceType>) throws {
        try serialize {
            for fork in forks where fork != .main {
                try performMergeIntoMain(from: fork, mergedContentFunc: mergedContentFunc)
            }
            for fork in forks where fork != .main {
                let action = try performMergeFromMain(into: fork, mergedContentFunc: mergedContentFunc)
                assert(action == .fastForward || action == .none)
            }
        }
    }
    
    func performMergeAllForks(into toFork: Fork, mergedContentFunc: (ConflictingCommits<ResourceType>, Commit<ResourceType>) throws -> CommitContent<ResourceType>) throws {
        try serialize {
            for fork in forks where fork != toFork && fork != .main {
                try performMergeIntoMain(from: fork, mergedContentFunc: mergedContentFunc)
            }
            try performMergeFromMain(into: toFork, mergedContentFunc: mergedContentFunc)
        }
    }
    
    func performSyncAllForks(mergedContentFunc: (ConflictingCommits<ResourceType>, Commit<ResourceType>) throws -> CommitContent<ResourceType>) throws {
        try performSyncMain(with: forks, mergedContentFunc: mergedContentFunc)
    }
}

