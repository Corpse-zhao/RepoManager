import SwiftUI

@main
struct RepoManagerApp: App {
    @StateObject private var vm = RepoViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var vm: RepoViewModel

    var body: some View {
        Group {
            if vm.config.isValid {
                MainTabView()
            } else {
                SetupView()
            }
        }
        .alert(vm.alertMessage ?? "", isPresented: $vm.showAlert) {
            Button("好", role: .cancel) {}
        }
    }
}
