import Testing
import Foundation
import Forked
import ForkedModel
@testable import ForkedMerge


struct Item: Identifiable, Equatable {
    let id: String
    let value: Int
}

@ForkedModel
struct MergeableItem: Identifiable, Equatable {
    var id: String = UUID().uuidString
    @Merged var value: AccumulatingInt = .init(0)
}

extension Array where Element == Int {
    var itemsArray: [Item] {
        map { .init(id: "\($0)", value: $0) }
    }
}

struct ArrayOfIdentifiableMergerSuite {
    let ancestor: [Item] = [1, 2, 3].itemsArray
    let merger = ArrayOfIdentifiableMerger<Item>()
    let mergeableMerger = ArrayOfIdentifiableMerger<MergeableItem>()

    @Test func mergeOneSidedAppend() throws {
        let updated = [1, 2, 3, 3, 4].itemsArray
        let merged = try merger.merge(updated, withSubordinate: ancestor, commonAncestor: ancestor)
        #expect(merged.map({ $0.value }) == [1, 2, 3, 4])
    }
    
    @Test func mergeOneSidedRemove() throws {
        let updated = [1, 3].itemsArray
        let merged = try merger.merge(updated, withSubordinate: ancestor, commonAncestor: ancestor)
        #expect(merged.map({ $0.value }) == [1, 3])
    }
    
    @Test func mergeOneSidedAddAndRemove() throws {
        let updated = [1, 3, 4].itemsArray
        let merged = try merger.merge(updated, withSubordinate: ancestor, commonAncestor: ancestor)
        #expect(merged.map({ $0.value }) == [1, 3, 4])
    }
    
    @Test func mergeTwoSidedInsert() throws {
        let updated1 = [1, 2, 4, 3].itemsArray
        let updated2 = [1, 2, 4, 3, 5].itemsArray
        let merged = try merger.merge(updated2, withSubordinate: updated1, commonAncestor: ancestor)
        #expect(merged.map({ $0.value }) == [1, 2, 4, 3, 5])
    }
    
    @Test func mergeTwoSidedDeletes() throws {
        let updated1 = [1, 2, 1].itemsArray
        let updated2 = [1, 3, 1].itemsArray
        let merged = try merger.merge(updated2, withSubordinate: updated1, commonAncestor: ancestor)
        #expect(merged.map({ $0.value }) == [1])
    }
    
    @Test func mergeTwoSidedInsertAndDelete() throws {
        let updated1 = [1, 2, 4].itemsArray
        let updated2 = [1, 5, 3].itemsArray
        let merged = try merger.merge(updated2, withSubordinate: updated1, commonAncestor: ancestor)
        #expect(merged.map({ $0.value }) == [1, 5, 4])
    }
    
    @Test func mergeMergeableMultipleChanges() throws {
        let ancestor = [MergeableItem(id: "a", value: .init(1))]
        var updated1 = ancestor
        var updated2 = ancestor
        updated1.append(MergeableItem(id: "b", value: .init(2))) // [1, 2]
        updated2.append(MergeableItem(id: "c", value: .init(3)))
        updated1[0].value.value = 4 // [4, 2]
        updated2[0].value.value = 5 // [5, 3]
        updated2[1].value.value = 7 // [5, 7]
        
        let merged = try mergeableMerger.merge(updated2, withSubordinate: updated1, commonAncestor: ancestor) // [8, 7, 2]
        #expect(merged.count == 3)
        #expect(merged[0].value.value == 8)
        #expect(merged[1].value.value == 7)
        #expect(merged[2].value.value == 2)
    }
}


//extension MergeableValue: Identifiable where T: Identifiable, T.ID == UUID {
//    public var id: UUID { value.id }
//}

@ForkedModel
struct IntWithID: Identifiable, Equatable, Sendable {
    var id: String = ""
    @Merged var intValue: MergeableValue<Int> = .init(0)
}

extension Array where Element == Int {
    var intIDArray: [IntWithID] {
        map { .init(id: "\($0)", intValue: .init($0)) }
    }
}

struct ConfusionAboutHowMergeWorks {

    @ForkedModel
    struct ItemArray: Equatable {
        @Merged(using: .arrayOfIdentifiableMerge) var items: [IntWithID] = []
    }

    @Observable
    @MainActor
    final class Store {
        typealias RepoType = AtomicRepository<ItemArray>
        let repo: RepoType
        let forkedModel: ForkedResource<RepoType>

        init() throws {
            repo =  AtomicRepository()
            forkedModel = try ForkedResource(repository: repo)
        }
    }

    @Test func thisPasses() async throws {
        let store = try await Store()
        let model = store.forkedModel

        let items = ItemArray(items: [0, 0, 0].intIDArray)
        try model.update(.main, with: items)

        let f1 = Fork(name: "f1")
        try model.create(f1)
        let f2 = Fork(name: "f2")
        try model.create(f2)

        try model.syncAllForks()

        var f1Items = try model.resource(of: f1)!
        #expect(f1Items.items.count == 3)
        #expect(f1Items.items.map { $0.intValue.value } == [0, 0, 0])

        f1Items.items[1].intValue.value = 1
        #expect(f1Items.items.map { $0.intValue.value } == [0, 1, 0])
        try model.update(f1, with: f1Items)

        try model.syncAllForks()

        var f2Items = try model.resource(of: f2)!
        #expect(f2Items.items.count == 3)
        #expect(f2Items.items.map { $0.intValue.value } == [0, 1, 0])

        f2Items.items[2].intValue.value = 2
        try model.update(f2, with: f2Items)

        try model.syncAllForks()

        let updatedItems: ItemArray
        updatedItems = try model.resource(of: .main)!
        #expect(updatedItems.items.map { $0.intValue.value } == [0, 1, 2])
    }

    @Test func thisFails() async throws {
        let store = try await Store()
        let model = store.forkedModel

        let items = ItemArray(items: [0, 0, 0].intIDArray)
        try model.update(.main, with: items)

        let f1 = Fork(name: "f1")
        try model.create(f1)
        let f2 = Fork(name: "f2")
        try model.create(f2)
        try model.syncAllForks()

        // both f1Items and f2Items start with [0, 0, 0] from main
        var f1Items = try model.resource(of: f1)!
        #expect(f1Items.items.count == 3)
        #expect(f1Items.items.map { $0.intValue.value } == [0, 0, 0])

        var f2Items = try model.resource(of: f2)!
        #expect(f2Items.items.count == 3)
        #expect(f2Items.items.map { $0.intValue.value } == [0, 0, 0])

        // f1 is updated to [0, 1, 0]
        f1Items.items[1].intValue.value = 1
        #expect(f1Items.items.map { $0.intValue.value } == [0, 1, 0])
        try model.update(f1, with: f1Items)
        // merge this change into main
        try model.mergeIntoMain(from: f1)

        var updatedItems: ItemArray
        // now main has [0, 1, 0]
        updatedItems = try model.resource(of: .main)!
        #expect(updatedItems.items.map { $0.intValue.value } == [0, 1, 0])

        // f2 is updated to [0, 0, 2]
        f2Items.items[2].intValue.value = 2
        #expect(f2Items.items.map { $0.intValue.value } == [0, 0, 2])
        try model.update(f2, with: f2Items)
        // merge this change into main
        try model.mergeIntoMain(from: f2)

        // why doesn't main now have [0, 1, 2]
        updatedItems = try model.resource(of: .main)!
        #expect(updatedItems.items.map { $0.intValue.value } == [0, 1, 2])
    }


}
