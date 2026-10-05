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
    let savedOrder = UserDefaults.standard.stringArray(forKey: "favorites.order")
    let savedRecents = UserDefaults.standard.stringArray(forKey: "channels.recent")
    guard store.channels.count >= 2 else { exit(1) }
    let second = store.channels[1]
    store.selectedChannelID = first.id
    store.selectedChannelID = second.id
    store.returnToPreviousChannel()
    guard store.selectedChannelID == first.id, store.previousChannelID == second.id,
          store.recentIDs == [first.id, second.id] else { exit(1) }
    store.returnToPreviousChannel()
    guard store.selectedChannelID == second.id else { exit(1) }
    store.toggleFavorite(second.id)
    store.moveFavorite(second.id, by: -1)
    store.selectedGroup = "__favoritos"
    guard store.visibleChannels.map(\.id) == [second.id, first.id] else { exit(1) }
    store.selectedGroup = "__recientes"
    guard store.visibleChannels.map(\.id) == [second.id, first.id] else { exit(1) }
    let third = store.channels[2]
    store.selectedChannelID = third.id
    store.selectedGroup = "__todos"
    store.selectedGroup = "__recientes"
    store.moveSelection(by: 1)
    guard store.selectedChannelID == second.id else { exit(1) }
    store.moveSelection(by: 1)
    guard store.selectedChannelID == first.id else { exit(1) }
    let previous = store.previousChannelID
    store.selectedChannelID = first.id
    guard store.previousChannelID == previous else { exit(1) }
    store.searchText = "unlikely-no-channel"
    guard store.visibleChannels.isEmpty else { exit(1) }
    store.searchText = ""
    for index in 0..<30 { store.selectedChannelID = "fixture-\(index)" }
    guard store.recentIDs.count == 20, Set(store.recentIDs).count == 20 else { exit(1) }
    guard savedOrder == UserDefaults.standard.stringArray(forKey: "favorites.order"),
          savedRecents == UserDefaults.standard.stringArray(forKey: "channels.recent") else { exit(1) }
    let suite = "MacIPTV.NavigationSmoke.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    preferences.set([first.id], forKey: "favorites.ids")
    let persistent = AppStore(defaults: preferences)
    persistent.channels = store.channels
    persistent.toggleFavorite(second.id)
    persistent.moveFavorite(second.id, by: -1)
    persistent.selectedChannelID = first.id
    persistent.selectedChannelID = second.id
    let restored = AppStore(defaults: preferences)
    guard restored.favoriteOrder == [second.id, first.id],
          restored.favorites == Set([first.id, second.id]),
          restored.recentIDs == [second.id, first.id] else { exit(1) }
    print("PASS: migration and navigation preferences survive a new AppStore")
    print("PASS: previous channel, ordered favorites, recent filtering and 20-entry history; demo preserves preferences")
    exit(0)
}
RunLoop.main.run()
