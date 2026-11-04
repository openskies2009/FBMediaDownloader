import SwiftUI

struct ContentView: View {
    @StateObject private var engine = FBDownloaderEngine()
    @StateObject private var loginManager = FBLoginManager()
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Facebook Media Downloader")
                    .font(.title)
                    .bold()
                
                Divider()
                
                // 1. Authentication
                GroupBox("1. Access Token") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button(action: {
                                loginManager.loginWithFacebook { token in
                                    if let token = token {
                                        engine.fbToken = token
                                        engine.fetchFacebookPages()
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "person.badge.key.fill")
                                    Text("Log in with Facebook")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(loginManager.isLoading)
                            
                            SecureField("Or Paste Access Token Here...", text: $engine.fbToken)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Load Pages") {
                                engine.fetchFacebookPages()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(engine.fbToken.isEmpty || engine.isFetchingPages)
                        }
                        
                        if engine.isFetchingPages || loginManager.isLoading {
                            ProgressView("Fetching managed pages...").controlSize(.small)
                        }
                        
                        if let err = engine.errorMessage ?? loginManager.errorMessage {
                            Text(err).foregroundColor(.red).font(.caption)
                        }
                    }
                    .padding(8)
                }
                
                // 2. Date Filters & Destination
                GroupBox("2. Date Filters & Destination") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            DatePicker("Start Date", selection: $engine.startDate, displayedComponents: .date)
                                .frame(maxWidth: 220)
                            
                            if !engine.noEndDate {
                                DatePicker("End Date", selection: $engine.endDate, displayedComponents: .date)
                                    .frame(maxWidth: 220)
                            }
                            
                            Toggle("No End Date (Continuous)", isOn: $engine.noEndDate)
                        }
                        
                        HStack {
                            Text("Destination:")
                            Text(engine.localDestPath.isEmpty ? "None Selected" : engine.localDestPath)
                                .foregroundColor(engine.localDestPath.isEmpty ? .red : .blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    engine.saveSecurityBookmark(for: url)
                                }
                            }
                        }
                        
                        Divider()
                        
                        Toggle("Auto-Organize into Date Folders", isOn: $engine.autoOrganize)
                            .toggleStyle(.switch)
                        
                        if engine.autoOrganize {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Pattern:").font(.caption).foregroundColor(.secondary)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill").foregroundColor(.blue)
                                    Text("/")
                                    ForEach(Array(engine.scanPattern.enumerated()), id: \.offset) { idx, token in
                                        HStack(spacing: 4) {
                                            Text(token)
                                            Button(action: { engine.scanPattern.remove(at: idx) }) {
                                                Image(systemName: "xmark").font(.system(size: 8))
                                            }.buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)
                                        
                                        if idx < engine.scanPattern.count - 1 { Text("/") }
                                    }
                                }
                                .padding(6)
                                .background(Color.black.opacity(0.1))
                                .cornerRadius(6)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(DateToken.allCases) { token in
                                            Button(token.rawValue) {
                                                if !engine.scanPattern.contains(token.rawValue) {
                                                    engine.scanPattern.append(token.rawValue)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                
                // 3. Page Selection List (Expands vertically)
                GroupBox("3. Select Pages to Download (\(engine.selectedPageIDs.count) selected)") {
                    VStack {
                        if engine.fetchedPages.isEmpty {
                            Text("Log in or enter token and click 'Load Pages' to view managed profiles.")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(maxHeight: .infinity)
                        } else {
                            HStack {
                                Button("Select All") {
                                    engine.selectedPageIDs = Set(engine.fetchedPages.map { $0.id })
                                }.buttonStyle(.plain).foregroundColor(.blue)
                                
                                Text("|")
                                
                                Button("Deselect All") {
                                    engine.selectedPageIDs.removeAll()
                                }.buttonStyle(.plain).foregroundColor(.red)
                                
                                Spacer()
                            }
                            .font(.caption)
                            .padding(.bottom, 4)
                            
                            List(engine.fetchedPages) { page in
                                HStack {
                                    Toggle("", isOn: Binding(
                                        get: { engine.selectedPageIDs.contains(page.id) },
                                        set: { isSelected in
                                            if isSelected { engine.selectedPageIDs.insert(page.id) }
                                            else { engine.selectedPageIDs.remove(page.id) }
                                        }
                                    ))
                                    .labelsHidden()
                                    
                                    AsyncImage(url: URL(string: page.picture?.data?.url ?? page.picture?.data?.src ?? "")) { phase in
                                        if let img = phase.image { img.resizable().scaledToFill() }
                                        else { Image(systemName: "person.circle.fill").resizable() }
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                                    
                                    Text(page.name).bold()
                                    Spacer()
                                }
                            }
                            .listStyle(.inset)
                            .frame(minHeight: 250, maxHeight: .infinity)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(16)
            
            Divider()
            
            // Bottom Execution Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.statusMessage).bold()
                    if engine.isDownloading {
                        ProgressView(value: engine.downloadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 250)
                    }
                }
                
                Spacer()
                
                Button(action: { engine.startDownload() }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Start Download")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .disabled(engine.isDownloading || engine.selectedPageIDs.isEmpty || engine.localDestPath.isEmpty)
            }
            .padding(15)
            .background(Material.bar)
        }
        .frame(minWidth: 700, minHeight: 700)
        .onAppear {
            if !engine.fbToken.isEmpty && engine.fetchedPages.isEmpty {
                engine.fetchFacebookPages()
            }
        }
    }
}
