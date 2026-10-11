//
//  BrockerView.swift
//  Broke
//
//  Created by Oz Tamir on 22/08/2024.
//
import SwiftUI
import CoreNFC
import SFSymbolsPicker
import FamilyControls
import ManagedSettings

enum BrokerAlert: Identifiable {
    case wrongTag
    case createTag
    case tagCreated(success: Bool)
    case notAuthorized
    case emptyProfile
    case emergencyUnblock

    var id: String {
        switch self {
        case .wrongTag: return "wrongTag"
        case .createTag: return "createTag"
        case .tagCreated(let success): return "tagCreated-\(success)"
        case .notAuthorized: return "notAuthorized"
        case .emptyProfile: return "emptyProfile"
        case .emergencyUnblock: return "emergencyUnblock"
        }
    }
}

struct BrokerView: View {
    @EnvironmentObject private var appBlocker: AppBlocker
    @EnvironmentObject private var profileManager: ProfileManager
    @EnvironmentObject private var alarmManager: TagAlarmManager
    @StateObject private var nfcReader = NFCReader()
    
    // Random per-install phrase, so a tag written from the public source code can't unlock this phone
    private static let tagPhrase: String = {
        let key = "tagPhrase"
        if let phrase = UserDefaults.standard.string(forKey: key) {
            return phrase
        }
        let phrase = "BROKE-\(UUID().uuidString)"
        UserDefaults.standard.set(phrase, forKey: key)
        return phrase
    }()
    
    @State private var activeAlert: BrokerAlert?
    @State private var showAlarms = false
    
    private var isBlocking : Bool {
        get {
            return appBlocker.isBlocking
        }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 0) {
                        blockOrUnblockButton(geometry: geometry)
                        
                        if !isBlocking {
                            Divider()
                            
                            ProfilesPicker(profileManager: profileManager)
                                .frame(height: geometry.size.height / 2)
                                .transition(.move(edge: .bottom))
                        }
                    }
                    .background(isBlocking ? Color("BlockingBackground") : Color("NonBlockingBackground"))
                }
            }
            .navigationBarItems(leading: alarmsButton, trailing: createTagButton)
            .alert(item: $activeAlert) { alert in
                makeAlert(alert)
            }
            .sheet(isPresented: $showAlarms) {
                AlarmsView()
                    .environmentObject(alarmManager)
            }
        }
        .animation(.spring(), value: isBlocking)
    }
    
    private func makeAlert(_ alert: BrokerAlert) -> Alert {
        switch alert {
        case .wrongTag:
            return Alert(
                title: Text("Not a Broker Tag"),
                message: Text("You can create a new Broker tag using the + button"),
                dismissButton: .default(Text("OK"))
            )
        case .createTag:
            return Alert(
                title: Text("Create Broker Tag"),
                message: Text("Do you want to create a new Broker tag?"),
                primaryButton: .default(Text("Create")) { createBrokerTag() },
                secondaryButton: .cancel()
            )
        case .tagCreated(let success):
            return Alert(
                title: Text("Tag Creation"),
                message: Text(success ? "Broker tag created successfully!" : "Failed to create Broker tag. Please try again."),
                dismissButton: .default(Text("OK"))
            )
        case .notAuthorized:
            return Alert(
                title: Text("Screen Time Access Needed"),
                message: Text("Broke needs Screen Time permission to block apps."),
                primaryButton: .default(Text("Grant Access")) {
                    Task { await appBlocker.requestAuthorization() }
                },
                secondaryButton: .cancel()
            )
        case .emptyProfile:
            return Alert(
                title: Text("Nothing to Block"),
                message: Text("The \"\(profileManager.currentProfile.name)\" profile has no apps, categories or websites. Long-press it to edit."),
                dismissButton: .default(Text("OK"))
            )
        case .emergencyUnblock:
            return Alert(
                title: Text("Emergency Unblock"),
                message: Text("This unblocks without your tag. You have \(appBlocker.emergencyUnblocksRemaining) left and they don't come back."),
                primaryButton: .destructive(Text("Unblock")) {
                    withAnimation(.spring()) {
                        appBlocker.emergencyUnblock()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    @ViewBuilder
    private func blockOrUnblockButton(geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            if let kind = alarmManager.activeKind {
                Label(kind == .wakeUp ? "Wake-up alarm" : "Bedtime alarm", systemImage: kind.icon)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(kind == .wakeUp ? Color.orange : Color.indigo))
                    .padding(.bottom, 8)
            }
            
            Text(scanCaption)
                .font(.caption)
                .opacity(0.75)
                .transition(.scale)
            
            Button(action: {
                withAnimation(.spring()) {
                    scanTag()
                }
            }) {
                Image(isBlocking ? "RedIcon" : "GreenIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: geometry.size.height / 3)
            }
            .transition(.scale)
            
            if isBlocking && appBlocker.emergencyUnblocksRemaining > 0 {
                Button("Emergency unblock (\(appBlocker.emergencyUnblocksRemaining) left)") {
                    activeAlert = .emergencyUnblock
                }
                .font(.caption)
                .opacity(0.6)
                .padding(.top, 24)
            }
            
            #if DEBUG
            // Lets the full flow be tested without a physical tag; never in release builds
            Button("Simulate tag scan") {
                withAnimation(.spring()) {
                    scanTag(simulated: true)
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .padding(.top, 12)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: isBlocking ? geometry.size.height : geometry.size.height / 2)
        .animation(.spring(), value: isBlocking)
    }
    
    private var scanCaption: String {
        switch alarmManager.activeKind {
        case .wakeUp:
            return "Tap and scan your tag to stop the alarm"
        case .bedtime:
            return isBlocking ? "Tap and scan your tag to stop the alarm" : "Brick your phone to stop the alarm"
        case nil:
            return isBlocking ? "Tap to unblock" : "Tap to block"
        }
    }
    
    // simulated: skip NFC and act as if the real tag was scanned (debug builds only)
    private func scanTag(simulated: Bool = false) {
        let alarmKind = alarmManager.activeKind
        // A wake-up alarm, or a bedtime alarm once already blocked, is dismissed without toggling
        let togglesBlocking = !(alarmKind == .wakeUp || (alarmKind == .bedtime && isBlocking))
        
        if togglesBlocking {
            guard appBlocker.isAuthorized else {
                activeAlert = .notAuthorized
                return
            }
            guard isBlocking || !profileManager.currentProfile.isEmpty else {
                activeAlert = .emptyProfile
                return
            }
        }
        
        let handleScan = { (payload: String) in
            guard payload == Self.tagPhrase else {
                activeAlert = .wrongTag
                NSLog("Wrong Tag!\nPayload: \(payload)")
                return
            }
            
            if togglesBlocking {
                NSLog("Toggling block")
                appBlocker.toggleBlocking(for: profileManager.currentProfile)
            }
            if alarmKind == .wakeUp || (alarmKind == .bedtime && appBlocker.isBlocking) {
                alarmManager.endSession()
            }
        }
        
        if simulated {
            handleScan(Self.tagPhrase)
        } else {
            nfcReader.scan(completion: handleScan)
        }
    }
    
    @ViewBuilder
    private var alarmsButton: some View {
        if TagAlarmManager.isSupported {
            Button(action: {
                showAlarms = true
            }) {
                Image(systemName: "alarm")
            }
        }
    }
    
    private var createTagButton: some View {
        Button(action: {
            activeAlert = .createTag
        }) {
            Image(systemName: "plus")
        }
        // While blocking, writing a fresh tag would be a way to unblock without the real one
        .disabled(isBlocking || !NFCNDEFReaderSession.readingAvailable)
    }
    
    private func createBrokerTag() {
        nfcReader.write(Self.tagPhrase) { success in
            activeAlert = .tagCreated(success: success)
        }
    }
}
