//
//  TeamSpaceSettingsView.swift
//  md-preview
//
//  Team Space: sign in with GitHub, pick the repository, and see how
//  syncing is going.
//

import SwiftUI

struct TeamSpaceSettingsView: View {
    @State private var teamSpace = TeamSpace.shared
    @State private var repositoryInput = ""

    var body: some View {
        Form {
            LabeledContent(columnLabel("GitHub")) {
                VStack(alignment: .leading, spacing: 6) {
                    account
                }
            }
            .settingsGroupGap()

            LabeledContent(columnLabel("Repository")) {
                VStack(alignment: .leading, spacing: 6) {
                    if let repository = teamSpace.repository {
                        HStack {
                            Text(repository).textSelection(.enabled)
                            Button(L("Disconnect")) { teamSpace.disconnect() }
                        }
                    } else {
                        HStack {
                            TextField("", text: $repositoryInput, prompt: Text(verbatim: "owner/name"))
                                .frame(width: 220)
                                .onSubmit(connect)
                            Button(L("Connect"), action: connect)
                                .disabled(!teamSpace.isSignedIn || teamSpace.isConnecting
                                    || repositoryInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    SettingsCaption(L("Files sync with this repository’s default branch, in a Team Space folder you open from the sidebar’s folder menu."))
                }
            }
            .settingsGroupGap()

            LabeledContent(columnLabel("Sync every")) {
                Picker("", selection: $teamSpace.interval) {
                    ForEach(TeamSpace.Interval.allCases) { interval in
                        Text(Duration.seconds(interval.rawValue)
                            .formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                            .tag(interval)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .settingsGroupGap()

            LabeledContent(columnLabel("Status")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusText)
                        .foregroundStyle(isFailure ? .red : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !teamSpace.conflicts.isEmpty {
                        Text(L("Changed here and on GitHub:"))
                        ForEach(teamSpace.conflicts, id: \.path) { conflict in
                            HStack {
                                Text(conflict.path).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                ForEach(TeamSpaceSyncEngine.Resolution.allCases, id: \.self) { resolution in
                                    Button(resolution.title) { teamSpace.resolve(conflict, with: resolution) }
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    HStack {
                        Button(L("Sync Now")) { teamSpace.syncNow() }
                            .disabled(!teamSpace.canSync || teamSpace.status == .syncing)
                        Button(L("Show in Sidebar")) { teamSpace.showInSidebar() }
                            .disabled(teamSpace.repository == nil)
                    }
                }
            }
        }
        .formStyle(.columns)
    }

    @ViewBuilder
    private var account: some View {
        if let code = teamSpace.deviceCode {
            Text(String(format: L("Enter this code on GitHub: %@"), code.userCode))
                .textSelection(.enabled)
            HStack {
                Link(L("Open GitHub"), destination: code.verificationURL)
                Button(L("Cancel")) { teamSpace.cancelSignIn() }
            }
            SettingsCaption(L("The code is copied. Paste it on the page that opened, then allow access."))
        } else if teamSpace.isSignedIn {
            HStack {
                Text(teamSpace.login.map { String(format: L("Signed in as %@"), $0) } ?? L("Signed in"))
                Button(L("Sign Out")) { teamSpace.signOut() }
            }
        } else {
            Button(L("Sign in with GitHub…")) { teamSpace.signIn() }
            SettingsCaption(L("The app gets access to your repositories. The token stays in your Keychain."))
        }
    }

    private func connect() {
        teamSpace.connect(repositoryInput)
    }

    private var isFailure: Bool {
        if case .failed = teamSpace.status { true } else { false }
    }

    private var statusText: String {
        switch teamSpace.status {
        case .idle:
            teamSpace.repository == nil ? L("Not connected") : L("Waiting to sync")
        case .syncing:
            L("Syncing…")
        case .synced(let date):
            String(format: L("Up to date, checked at %@"), date.formatted(date: .omitted, time: .shortened))
        case .failed(let message):
            message
        }
    }
}
