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
            .navigationBarItems(trailing: createTagButton)
            .alert(item: $activeAlert) { alert in
                makeAlert(alert)
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
            Text(isBlocking ? "Tap to unblock" : "Tap to block")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: isBlocking ? geometry.size.height : geometry.size.height / 2)
        .animation(.spring(), value: isBlocking)
    }
    
    private func scanTag() {
        guard appBlocker.isAuthorized else {
            activeAlert = .notAuthorized
            return
        }
        guard isBlocking || !profileManager.currentProfile.isEmpty else {
            activeAlert = .emptyProfile
            return
        }
        
        nfcReader.scan { payload in
            if payload == Self.tagPhrase {
                NSLog("Toggling block")
                appBlocker.toggleBlocking(for: profileManager.currentProfile)
            } else {
                activeAlert = .wrongTag
                NSLog("Wrong Tag!\nPayload: \(payload)")
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
