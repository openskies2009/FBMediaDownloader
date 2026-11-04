import Foundation

// MARK: - Graph API Response Models
struct FBPageResponse: Codable {
    let data: [FBPage]?
}

struct FBPage: Codable, Identifiable {
    let id: String
    let name: String
    let picture: FBPictureDataWrapper?
    let accessToken: String?
    
    init(id: String, name: String, picture: FBPictureDataWrapper? = nil, accessToken: String? = nil) {
        self.id = id
        self.name = name
        self.picture = picture
        self.accessToken = accessToken
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, picture
        case accessToken = "access_token"
    }
}

struct FBPictureDataWrapper: Codable {
    let data: FBPictureURL?
}

struct FBPictureURL: Codable {
    let url: String?
    let src: String?
}

struct FBErrorResponse: Codable {
    let error: FBErrorDetail
}

struct FBErrorDetail: Codable {
    let message: String
}

// MARK: - Posts & Attachments
struct FBPostResponse: Codable {
    let data: [FBPost]?
    let paging: FBPaging?
}

struct FBPost: Codable {
    let id: String
    let message: String?
    let created_time: String?
    let attachments: FBAttachmentDataWrapper?
}

struct FBAttachmentDataWrapper: Codable {
    let data: [FBAttachment]?
}

struct FBAttachment: Codable {
    let media: FBMediaNode?
    let target: FBTargetNode?
    let subattachments: FBAttachmentDataWrapper?
}

struct FBMediaNode: Codable {
    let image: FBPictureURL?
    let source: String?
}

struct FBTargetNode: Codable {
    let id: String?
}

struct FBPaging: Codable {
    let next: String?
}

// MARK: - Available Date Tokens
enum DateToken: String, CaseIterable, Identifiable {
    case pageName = "PAGE_NAME"
    case year = "YYYY"
    case shortYear = "YY"
    case quarter = "QUARTER"
    case monthName = "MONTH"
    case monthNum = "MM"
    case day = "DD"
    
    var id: String { self.rawValue }
}
