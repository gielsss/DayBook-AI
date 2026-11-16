import SwiftUI

public struct MainView: View {
    @StateObject private var appState: AppState
    @AppStorage(DayBookAppearance.storageKey) private var appearance: DayBookAppearance = .system
    
    public init(appState: AppState? = nil) {
        _appState = StateObject(wrappedValue: appState ?? AppState())
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Demonstration Mode Notification Banner (Only shown when operating in sample/demo mode)
            if appState.isDemonstrationModeActive {
                DemoBannerView(appState: appState)
            }
            
            NavigationSplitView {
                // Sidebar Navigation
                List(AppTab.allCases, id: \.self, selection: $appState.selectedTab) { tab in
                    NavigationLink(value: tab) {
                        Label {
                            HStack {
                                Text(tab.rawValue)
                                Spacer()
                                if tab == .tasks {
                                    let activeCount = appState.tasks.filter { !$0.isCompleted }.count
                                    if activeCount > 0 {
                                        Text("\(activeCount)")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        } icon: {
                            Image(systemName: tab.systemImage)
                        }
                    }
                }
                .navigationTitle("DayBook AI")
                .listStyle(.sidebar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    DayBookLockup(markSize: 28, showsTagline: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                }
                .modifier(ColorfulSidebar(isColorful: appearance == .colorful))
                .frame(minWidth: 190, idealWidth: 210)
            } detail: {
                // Main Content View
                Group {
                    switch appState.selectedTab {
                    case .today:
                        TodayView(appState: appState)
                    case .tasks:
                        TasksView(appState: appState)
                    case .week:
                        WeekView(appState: appState)
                    case .settings:
                        SettingsView(appState: appState)
                    }
                }
                .frame(minWidth: 600, minHeight: 500)
                .background(Color.dbBackground)
                // New tasks found by a sync, shown on screen until you look at them.
                .overlay(alignment: .topTrailing) {
                    if appState.showNewTasksPanel && !appState.newlyFoundTasks.isEmpty {
                        NewTasksPanel(appState: appState)
                            .padding(16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.showNewTasksPanel)
                .toolbarBackground(Color.dbBackground, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
            }
        }
        // Rebuild with the new palette when the look changes.
        .id(appearance)
        .tint(.dbAccent)
        .accentColor(.dbAccent)
        .groupBoxStyle(DayBookGroupBoxStyle())
        // Navy ink on paper by day, cream on navy by night, like the marketing sheet.
        .foregroundStyle(Color.dbInk)
        .environmentObject(appState)
        .sheet(isPresented: $appState.showCreateActivitySheet) {
            CreateActivitySheet(appState: appState)
        }
        .sheet(isPresented: $appState.showDiscoveryLogSheet) {
            DiscoveryLogSheet(appState: appState)
        }
        .onAppear {
            QuickCaptureHotkeyManager.shared.register(appState: appState)
            DayBookAppearance.apply(appearance)
        }
        .onChange(of: appearance) { newValue in
            DayBookAppearance.apply(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DayBookAppearanceMenu()
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    appState.openQuickCapture()
                }) {
                    Label("Quick Capture", systemImage: "bolt.fill")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Quick Capture text or a screenshot from the clipboard (⌘⇧C)")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task { await appState.syncEverything() }
                }) {
                    if appState.isAnySyncRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Sync Everything", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Sync Everything: Apple Calendar, Canvas, Gradescope and email (also runs at 8 AM, 1 PM and 6 PM)")
                .disabled(appState.isAnySyncRunning)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    appState.showDiscoveryLogSheet = true
                }) {
                    Label("Discovery Log", systemImage: "tray.full")
                }
                .help("Discovery Log: what was read and why")
            }
        }
    }
}

/// Colorful mode: warm sand sidebar beside the cream page.
/// Brand sidebar in every look: sand by day, deep navy by night, deeper sand in Colorful.
private struct ColorfulSidebar: ViewModifier {
    let isColorful: Bool
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.dbSidebar)
    }
}
