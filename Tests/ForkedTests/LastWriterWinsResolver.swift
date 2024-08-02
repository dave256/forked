import Testing
@testable import Forked

struct LastWriterWinsResolverSuite {

    @Test func choosesMostRecent() throws {
        let resolver = LastWriteWinsResolver()
        let a: Commit<Int> = .init(content: .resource(0), version: .init(count: 0))
        let c1: Commit<Int> = .init(content: .resource(1), version: .init(count: 1))
        let c2: Commit<Int> = .init(content: .resource(2), version: .init(count: 1, timestamp: c1.version.timestamp.addingTimeInterval(0.001)))
        #expect(c1.version.timestamp < c2.version.timestamp)
        let m = try resolver.mergedContent(forConflicting: (c1,c2), withCommonAncestor: a)
        #expect(m == .resource(2))
    }
    
}
