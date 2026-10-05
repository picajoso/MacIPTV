import Foundation

Task { @MainActor in
    let store = AppStore()
    let before = UserDefaults.standard.stringArray(forKey: "favorites.ids")
    store.bootstrap(demo: true)
    guard let first = store.channels.first else { print("FAIL: demo has no channels"); exit(1) }
    store.toggleFavorite(first.id)
    store.selectedGroup = "__favoritos"
    guard store.visibleChannels.map(\.id) == [first.id] else {
        print("FAIL: favorites filter must show the selected demo favorite")
        exit(1)
    }
    print("PASS: favorites filter displays favorite channel")
    store.selectedGroup = first.group
    guard store.visibleChannels.allSatisfy({ $0.group == first.group }) else { exit(1) }
    store.selectedGroup = "__todos"
    guard store.visibleChannels.count == store.channels.count else {
        print("FAIL: All must restore every channel after group filtering")
        exit(1)
    }
    print("PASS: All restores every channel after group filtering")
    let after = UserDefaults.standard.stringArray(forKey: "favorites.ids")
    guard before == after else { print("FAIL: demo changed saved favorites"); exit(1) }
    print("PASS: demo favorites never alter saved favorites")
    exit(0)
}
RunLoop.main.run()
