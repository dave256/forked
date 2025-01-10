import Foundation
import Testing
@testable import Forked

struct FileRepositorySuite {
    @Test func createAndListForks() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        
        // Initially no forks
        #expect(repository.forks.isEmpty)
        
        // Create a fork
        let fork = Fork(name: "test")
        let initialCommit = Commit(content: .resource(Data()), version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        // Check fork exists
        #expect(repository.forks.count == 1)
        #expect(repository.forks.first?.name == "test")
    }
    
    @Test func storeAndRetrieveContent() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        let fork = Fork(name: "test")
        let initialCommit = Commit(content: .resource(Data()), version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        // Store new content
        let testData = "Hello, World!".data(using: .utf8)!
        let version = Version(count: 1, timestamp: .now)
        let commit = Commit(content: .resource(testData), version: version)
        try repository.store(commit, in: fork)
        
        // Retrieve and verify content
        let retrieved = try repository.content(of: fork, at: version)
        #expect(retrieved == .resource(testData))
    }
    
    @Test func versionListing() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        let fork = Fork(name: "test")
        let initialCommit = Commit(content: .resource(Data()), version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        // Check initial version
        var versions = try repository.versions(storedIn: fork)
        #expect(versions.count == 1)
        #expect(versions.contains(.initialVersion))
        
        // Add another version
        let version = Version(count: 1, timestamp: .now)
        let commit = Commit(content: .resource(Data()), version: version)
        try repository.store(commit, in: fork)
        
        // Check both versions exist
        versions = try repository.versions(storedIn: fork)
        #expect(versions.count == 2)
        #expect(versions.contains(.initialVersion))
        #expect(versions.contains(version))
    }
    
    @Test func deleteFork() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        let fork = Fork(name: "test")
        let initialCommit = Commit(content: .resource(Data()), version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        #expect(repository.forks.count == 1)
        try repository.delete(fork)
        #expect(repository.forks.isEmpty)
    }
    
    @Test func removeCommit() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        let fork = Fork(name: "test")
        let initialCommit = Commit(content: .resource(Data()), version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        let version = Version(count: 1, timestamp: .now)
        let commit = Commit(content: .resource(Data()), version: version)
        try repository.store(commit, in: fork)
        
        var versions = try repository.versions(storedIn: fork)
        #expect(versions.count == 2)
        
        try repository.removeCommit(at: version, from: fork)
        
        versions = try repository.versions(storedIn: fork)
        #expect(versions.count == 1)
        #expect(versions.contains(.initialVersion))
    }
    
    @Test func noneContent() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        let fork = Fork(name: "test")
        let initialCommit = Commit<Data>(content: .none, version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        let version = Version(count: 1, timestamp: .now)
        let commit = Commit<Data>(content: .none, version: version)
        try repository.store(commit, in: fork)
        
        let retrieved = try repository.content(of: fork, at: version)
        #expect(retrieved == .none)
    }
    
    @Test func errorConditions() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        let fork = Fork(name: "test")
        let nonExistentFork = Fork(name: "nonexistent")
        let version = Version(count: 1, timestamp: .now)
        
        // Accessing non-existent fork
        #expect(throws: Error.self) {
            try repository.versions(storedIn: nonExistentFork)
        }
        #expect(throws: Error.self) {
            try repository.content(of: nonExistentFork, at: version)
        }
        
        let initialCommit = Commit(content: .resource(Data()), version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        // Duplicate fork creation
        #expect(throws: Error.self) {
            try repository.create(fork, withInitialCommit: initialCommit)
        }
        
        // Accessing non-existent version
        #expect(throws: Error.self) {
            try repository.content(of: fork, at: version)
        }
        
        // Store commit and try to replace it
        let commit = Commit(content: .resource(Data()), version: version)
        try repository.store(commit, in: fork)
        #expect(throws: Error.self) {
            try repository.store(commit, in: fork)
        }
    }
    
    @Test func fileSystemState() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let repository = try FileRepository(rootDirectory: tempDirectory)
        let fork = Fork(name: "test")
        
        // Check root directory exists
        #expect(FileManager.default.fileExists(atPath: tempDirectory.path))
        
        // Create fork and verify directory structure
        let initialCommit = Commit(content: .resource(Data()), version: .initialVersion)
        try repository.create(fork, withInitialCommit: initialCommit)
        
        let forkDirectory = tempDirectory.appendingPathComponent("test")
        #expect(FileManager.default.fileExists(atPath: forkDirectory.path))
        
        // Verify initial version files
        let initialMetadataPath = forkDirectory.appendingPathComponent("0.metadata").path
        let initialDataPath = forkDirectory.appendingPathComponent("0").path
        #expect(FileManager.default.fileExists(atPath: initialMetadataPath))
        #expect(FileManager.default.fileExists(atPath: initialDataPath))
        
        // Add a .none commit and verify only metadata exists
        let version1 = Version(count: 1, timestamp: .now)
        let noneCommit = Commit<Data>(content: .none, version: version1)
        try repository.store(noneCommit, in: fork)
        
        let version1MetadataPath = forkDirectory.appendingPathComponent("1.metadata").path
        let version1DataPath = forkDirectory.appendingPathComponent("1").path
        #expect(FileManager.default.fileExists(atPath: version1MetadataPath))
        #expect(!FileManager.default.fileExists(atPath: version1DataPath))
        
        // Add a resource commit and verify both files exist
        let version2 = Version(count: 2, timestamp: .now)
        let resourceCommit = Commit(content: .resource(Data([1,2,3])), version: version2)
        try repository.store(resourceCommit, in: fork)
        
        let version2MetadataPath = forkDirectory.appendingPathComponent("2.metadata").path
        let version2DataPath = forkDirectory.appendingPathComponent("2").path
        #expect(FileManager.default.fileExists(atPath: version2MetadataPath))
        #expect(FileManager.default.fileExists(atPath: version2DataPath))
        
        // Remove a commit and verify files are deleted
        try repository.removeCommit(at: version2, from: fork)
        #expect(!FileManager.default.fileExists(atPath: version2MetadataPath))
        #expect(!FileManager.default.fileExists(atPath: version2DataPath))
        
        // Delete fork and verify directory is removed
        try repository.delete(fork)
        #expect(!FileManager.default.fileExists(atPath: forkDirectory.path))
    }
}
