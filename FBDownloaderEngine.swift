import Foundation
import Combine
import SwiftUI

@MainActor
class FBDownloaderEngine: ObservableObject {
    // Persisted Settings (@AppStorage)
    @AppStorage("saved_fb_token") var fbToken: String = ""
    @AppStorage("saved_local_dest_path") var localDestPath: String = ""
    @AppStorage("saved_auto_organize") var autoOrganize: Bool = true
    @AppStorage("saved_no_end_date") var noEndDate: Bool = false
    @AppStorage("saved_scan_pattern_raw") var scanPatternRaw: String = "PAGE_NAME,YYYY,MONTH"
    @AppStorage("saved_start_date_interval") var startDateInterval: Double = Date().addingTimeInterval(-30*86400).timeIntervalSince1970
    @AppStorage("saved_end_date_interval") var endDateInterval: Double = Date().timeIntervalSince1970
    @AppStorage("saved_dest_bookmark_data") var bookmarkData: Data = Data()
    
    var startDate: Date {
        get { Date(timeIntervalSince1970: startDateInterval) }
        set { startDateInterval = newValue.timeIntervalSince1970 }
    }
    
    var endDate: Date {
        get { Date(timeIntervalSince1970: endDateInterval) }
        set { endDateInterval = newValue.timeIntervalSince1970 }
    }
    
    var scanPattern: [String] {
        get { scanPatternRaw.components(separatedBy: ",").filter { !$0.isEmpty } }
        set { scanPatternRaw = newValue.joined(separator: ",") }
    }
    
    // Runtime State
    @Published var selectedPageIDs: Set<String> = []
    @Published var fetchedPages: [FBPage] = []
    @Published var fbPageNames: [String: String] = [:]
    @Published var fbPageTokens: [String: String] = [:]
    
    @Published var isFetchingPages: Bool = false
    @Published var isDownloading: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var downloadProgress: Double = 0.0
    @Published var errorMessage: String? = nil
    
    func saveSecurityBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            self.bookmarkData = bookmark
            self.localDestPath = url.path
        } catch {
            print("Failed to save bookmark: \(error)")
            self.localDestPath = url.path
        }
    }
    
    func fetchFacebookPages() {
        let cleanToken = fbToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            errorMessage = "Please enter an Access Token."
            return
        }
        
        isFetchingPages = true
        errorMessage = nil
        
        var components = URLComponents(string: "https://graph.facebook.com/v19.0/me/accounts")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,access_token,picture{url}"),
            URLQueryItem(name: "access_token", value: cleanToken)
        ]
        
        guard let url = components.url else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isFetchingPages = false
                guard let data = data else {
                    self.errorMessage = "Network request failed."
                    return
                }
                
                if let rawJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accounts = rawJSON["data"] as? [[String: Any]] {
                    
                    var pages = [FBPage]()
                    var nameMap = [String: String]()
                    var tokenMap = [String: String]()
                    
                    for acc in accounts {
                        if let id = acc["id"] as? String, let name = acc["name"] as? String {
                            let pageToken = acc["access_token"] as? String ?? cleanToken
                            tokenMap[id] = pageToken
                            nameMap[id] = name
                            
                            var pictureURL: String? = nil
                            if let picObj = acc["picture"] as? [String: Any],
                               let picData = picObj["data"] as? [String: Any],
                               let urlStr = picData["url"] as? String {
                                pictureURL = urlStr
                            }
                            
                            let wrapper = FBPictureDataWrapper(data: FBPictureURL(url: pictureURL, src: pictureURL))
                            pages.append(FBPage(id: id, name: name, picture: wrapper, accessToken: pageToken))
                        }
                    }
                    
                    self.fetchedPages = pages
                    self.fbPageNames = nameMap
                    self.fbPageTokens = tokenMap
                    return
                }
                
                if let errorDecoded = try? JSONDecoder().decode(FBErrorResponse.self, from: data) {
                    self.errorMessage = "Facebook API Error: \(errorDecoded.error.message)"
                    return
                }
                
                self.errorMessage = "Failed to parse Facebook response."
            }
        }.resume()
    }
    
    func startDownload() {
        let cleanToken = fbToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty, !selectedPageIDs.isEmpty, !localDestPath.isEmpty else {
            errorMessage = "Please complete credentials, page selection, and local destination."
            return
        }
        
        isDownloading = true
        downloadProgress = 0.0
        statusMessage = "Starting download..."
        
        let targetIDs = Array(selectedPageIDs)
        let pageNamesCopy = fbPageNames
        let pageTokensCopy = fbPageTokens
        let patternCopy = scanPattern
        let destPathCopy = localDestPath
        let savedBookmark = bookmarkData
        let autoOrgCopy = autoOrganize
        let startDt = startDate
        let endDt = endDate
        let noEnd = noEndDate
        
        Task.detached(priority: .userInitiated) {
            let totalPages = targetIDs.count
            
            for (index, pageID) in targetIDs.enumerated() {
                let pageName = pageNamesCopy[pageID] ?? pageID
                let pageToken = pageTokensCopy[pageID] ?? cleanToken
                
                await MainActor.run {
                    self.statusMessage = "Downloading \(pageName) (\(index + 1)/\(totalPages))..."
                    self.downloadProgress = Double(index) / Double(totalPages)
                }
                
                await self.executePageDownload(
                    pageID: pageID,
                    pageName: pageName,
                    pageToken: pageToken,
                    destPath: destPathCopy,
                    bookmarkData: savedBookmark,
                    startDate: startDt,
                    endDate: endDt,
                    noEndDate: noEnd,
                    autoOrganize: autoOrgCopy,
                    scanPattern: patternCopy
                )
            }
            
            await MainActor.run {
                self.isDownloading = false
                self.downloadProgress = 1.0
                self.statusMessage = "Download Complete!"
            }
        }
    }
}

extension FBDownloaderEngine {
    
    nonisolated private func resolveFolderStructure(pageName: String, date: Date, autoOrganize: Bool, scanPattern: [String]) -> [String] {
        guard autoOrganize && !scanPattern.isEmpty else { return [pageName] }
        
        let formatter = DateFormatter()
        var resolved = [String]()
        
        for token in scanPattern {
            switch token {
            case "PAGE_NAME":
                resolved.append(pageName)
            case "YYYY":
                formatter.dateFormat = "yyyy"
                resolved.append(formatter.string(from: date))
            case "YY":
                formatter.dateFormat = "yy"
                resolved.append(formatter.string(from: date))
            case "QUARTER":
                let month = Calendar.current.component(.month, from: date)
                resolved.append("Q\((month - 1) / 3 + 1)")
            case "MONTH":
                formatter.dateFormat = "MMMM"
                resolved.append(formatter.string(from: date))
            case "MM":
                formatter.dateFormat = "MM"
                resolved.append(formatter.string(from: date))
            case "DD":
                formatter.dateFormat = "dd"
                resolved.append(formatter.string(from: date))
            default:
                resolved.append(token)
            }
        }
        return resolved
    }
    
    nonisolated private func executePageDownload(
        pageID: String,
        pageName: String,
        pageToken: String,
        destPath: String,
        bookmarkData: Data,
        startDate: Date,
        endDate: Date,
        noEndDate: Bool,
        autoOrganize: Bool,
        scanPattern: [String]
    ) async {
        var resolvedURL: URL?
        var isStale = false
        
        if !bookmarkData.isEmpty {
            resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
        
        let targetRootURL = resolvedURL ?? URL(fileURLWithPath: destPath)
        
        let isAccessing = targetRootURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                targetRootURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let isoFormatter = ISO8601DateFormatter()
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let untilQuery = noEndDate ? "" : "&until=\(Int(endDate.timeIntervalSince1970))"
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 8.0
        sessionConfig.timeoutIntervalForResource = 30.0
        let session = URLSession(configuration: sessionConfig)
        
        var nextURLString: String? = "https://graph.facebook.com/v19.0/\(pageID)/posts?fields=id,message,created_time,attachments{media,target,subattachments}&since=\(startTimestamp)\(untilQuery)&limit=50&access_token=\(pageToken)"
        
        func setFileDates(url: URL, date: Date) {
            var resourceValues = URLResourceValues()
            resourceValues.creationDate = date
            resourceValues.contentModificationDate = date
            var mutableURL = url
            try? mutableURL.setResourceValues(resourceValues)
        }
        
        func createInternetShortcut(at linkURL: URL, pointingTo postURLString: String, date: Date) {
            let shortcutContent = """
            [InternetShortcut]
            URL=\(postURLString)
            """
            do {
                try shortcutContent.write(to: linkURL, atomically: true, encoding: .utf8)
                setFileDates(url: linkURL, date: date)
            } catch {
                print("Failed to create .url shortcut: \(error)")
            }
        }
        
        while let urlString = nextURLString, !urlString.isEmpty {
            guard let url = URL(string: urlString) else { break }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            guard let (data, response) = try? await session.data(for: request) else { break }
            
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 { break }
            
            guard let postResponse = try? JSONDecoder().decode(FBPostResponse.self, from: data) else { break }
            
            if let posts = postResponse.data {
                for post in posts {
                    let createdStr = post.created_time ?? ""
                    let postDate = isoFormatter.date(from: createdStr) ?? Date()
                    let postURLString = "https://www.facebook.com/\(post.id)"
                    
                    let folderParts = resolveFolderStructure(pageName: pageName, date: postDate, autoOrganize: autoOrganize, scanPattern: scanPattern)
                    var currentDir = targetRootURL
                    for part in folderParts { currentDir.appendPathComponent(part) }
                    
                    try? FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
                    
                    if let message = post.message, !message.isEmpty {
                        let txtFile = currentDir.appendingPathComponent("\(post.id).txt")
                        if !FileManager.default.fileExists(atPath: txtFile.path) {
                            try? message.write(to: txtFile, atomically: true, encoding: .utf8)
                            setFileDates(url: txtFile, date: postDate)
                        }
                    }
                    
                    func fetchFullResImageURL(targetID: String?, fallbackURL: String?) async -> String {
                        guard let targetID = targetID, !targetID.isEmpty else { return fallbackURL ?? "" }
                        let reqURLString = "https://graph.facebook.com/v19.0/\(targetID)?fields=images&access_token=\(pageToken)"
                        guard let reqURL = URL(string: reqURLString) else { return fallbackURL ?? "" }
                        
                        var req = URLRequest(url: reqURL)
                        req.timeoutInterval = 4.0
                        
                        if let (data, _) = try? await session.data(for: req),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let images = json["images"] as? [[String: Any]],
                           let largestImage = images.first,
                           let sourceURL = largestImage["source"] as? String {
                            return sourceURL
                        }
                        return fallbackURL ?? ""
                    }
                    
                    var mediaItems: [(url: String, ext: String)] = []
                    
                    if let atts = post.attachments?.data {
                        for att in atts {
                            let fallback = att.media?.image?.url ?? att.media?.image?.src
                            if let videoSrc = att.media?.source {
                                mediaItems.append((videoSrc, "mp4"))
                            } else if let targetID = att.target?.id {
                                let fullResURL = await fetchFullResImageURL(targetID: targetID, fallbackURL: fallback)
                                if !fullResURL.isEmpty { mediaItems.append((fullResURL, "jpg")) }
                            } else if let fallback = fallback {
                                mediaItems.append((fallback, "jpg"))
                            }
                            
                            if let subs = att.subattachments?.data {
                                for sub in subs {
                                    let subFallback = sub.media?.image?.url ?? sub.media?.image?.src
                                    if let videoSrc = sub.media?.source {
                                        mediaItems.append((videoSrc, "mp4"))
                                    } else if let targetID = sub.target?.id {
                                        let fullResURL = await fetchFullResImageURL(targetID: targetID, fallbackURL: subFallback)
                                        if !fullResURL.isEmpty { mediaItems.append((fullResURL, "jpg")) }
                                    } else if let subFallback = subFallback {
                                        mediaItems.append((subFallback, "jpg"))
                                    }
                                }
                            }
                        }
                    }
                    
                    for (i, item) in mediaItems.enumerated() {
                        let baseFileName = "\(post.id)_\(i)"
                        let destFileURL = currentDir.appendingPathComponent("\(baseFileName).\(item.ext)")
                        let shortcutFileURL = currentDir.appendingPathComponent("\(baseFileName).url")
                        
                        if !FileManager.default.fileExists(atPath: destFileURL.path) {
                            if let remoteURL = URL(string: item.url) {
                                var fileReq = URLRequest(url: remoteURL)
                                fileReq.timeoutInterval = 25.0
                                if let (mediaData, _) = try? await session.data(for: fileReq) {
                                    try? mediaData.write(to: destFileURL, options: .atomic)
                                    setFileDates(url: destFileURL, date: postDate)
                                    createInternetShortcut(at: shortcutFileURL, pointingTo: postURLString, date: postDate)
                                }
                            }
                        }
                    }
                }
            }
            nextURLString = postResponse.paging?.next
        }
    }
}
