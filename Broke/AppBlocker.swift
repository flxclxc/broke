//
//  AppBlocker.swift
//  Broke
//
//  Created by Oz Tamir on 22/08/2024.
//
import SwiftUI
import ManagedSettings
import FamilyControls

class AppBlocker: ObservableObject {
    static let maxEmergencyUnblocks = 5

    let store = ManagedSettingsStore()
    @Published var isBlocking = false
    @Published var isAuthorized = false
    @Published var emergencyUnblocksRemaining = AppBlocker.maxEmergencyUnblocks
    
    init() {
        loadBlockingState()
        Task {
            await requestAuthorization()
        }
    }
    
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
        } catch {
            print("Failed to request authorization: \(error)")
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
    }
    
    func toggleBlocking(for profile: Profile) {
        guard isAuthorized else {
            print("Not authorized to block apps")
            return
        }
        
        isBlocking.toggle()
        saveBlockingState()
        applyBlockingSettings(for: profile)
    }
    
    // Escape hatch for a lost tag; limited so it can't replace the tag
    func emergencyUnblock() {
        guard isBlocking, emergencyUnblocksRemaining > 0 else { return }
        
        emergencyUnblocksRemaining -= 1
        isBlocking = false
        saveBlockingState()
        clearBlockingSettings()
    }
    
    func applyBlockingSettings(for profile: Profile) {
        guard isBlocking else {
            clearBlockingSettings()
            return
        }
        
        NSLog("Blocking \(profile.appTokens.count) apps, \(profile.webDomainTokens.count) websites")
        store.shield.applications = profile.appTokens.isEmpty ? nil : profile.appTokens
        store.shield.applicationCategories = profile.categoryTokens.isEmpty ? ShieldSettings.ActivityCategoryPolicy.none : .specific(profile.categoryTokens)
        store.shield.webDomains = profile.webDomainTokens.isEmpty ? nil : profile.webDomainTokens
        store.shield.webDomainCategories = profile.categoryTokens.isEmpty ? ShieldSettings.ActivityCategoryPolicy.none : .specific(profile.categoryTokens)
        // Deleting the app would drop its shields, so prevent it while blocking
        store.application.denyAppRemoval = true
    }
    
    private func clearBlockingSettings() {
        store.shield.applications = nil
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.shield.webDomains = nil
        store.shield.webDomainCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.application.denyAppRemoval = false
    }
    
    private func loadBlockingState() {
        isBlocking = UserDefaults.standard.bool(forKey: "isBlocking")
        if UserDefaults.standard.object(forKey: "emergencyUnblocksRemaining") != nil {
            emergencyUnblocksRemaining = UserDefaults.standard.integer(forKey: "emergencyUnblocksRemaining")
        }
    }
    
    private func saveBlockingState() {
        UserDefaults.standard.set(isBlocking, forKey: "isBlocking")
        UserDefaults.standard.set(emergencyUnblocksRemaining, forKey: "emergencyUnblocksRemaining")
    }
}
