//
//  Reports.swift
//  FireAlarm
//
//  Created by Ashish Ahuja on 24/04/17.
//
//

import Foundation
import SwiftStack
import SwiftChatSE
import Dispatch

struct Report {
    let id: Int
    let when: Date
    let difference: Int?
    
    let messages: [(host: ChatRoom.Host, roomID: Int, messageID: Int)]
    let details: String?
    
    init(
        id: Int,
        when: Date,
        difference: Int?,
        messages: [(host: ChatRoom.Host, roomID: Int, messageID: Int)] = [],
        details: String? = nil
        ) {
        
        self.id = id
        self.when = when
        self.difference = difference
        self.messages = messages
        self.details = details
    }
    
    init?(json: [String:Any]) {
        guard let id = json["id"] as? Int, let when = json["t"] as? Int else {
            return nil
        }
        
        let messages = (json["m"] as? [[String:Any]])?.flatMap { messageJSON in
            guard let host = (messageJSON["h"] as? Int).map ({ChatRoom.Host(rawValue: $0)}) ?? nil,
                let room = messageJSON["r"] as? Int,
                let message = messageJSON["m"] as? Int else {
                    return nil
            }
            
            return (host: host, roomID: room, messageID: message)
            } as [(host: ChatRoom.Host, roomID: Int, messageID: Int)]? ?? []
        let why = json["w"] as? String
        
        self.init(
            id: id,
            when: Date(timeIntervalSince1970: TimeInterval(when)),
            difference: (json["d"] as? Int),
            messages: messages,
            details: why
        )
    }
    
    var json: [String:Any] {
        var result = [String:Any]()
        result["id"] = id
        result["t"] = Int(when.timeIntervalSince1970)
        if let d = difference {
            result["d"] = d
        }
        
        if let w = details {
            result["w"] = w
        }
        
        
        result["m"] = messages.map {
            ["h":$0.host.rawValue, "r":$0.roomID, "m":$0.messageID]
        }
        
        return result
    }
}

var reportedPosts = [Report]()

class Reporter {
    var postFetcher: PostFetcher!
    let rooms: [ChatRoom]
    
    var staticDB: DatabaseConnection
    
    var filters = [Filter]()
    
    var blacklistManager: BlacklistManager
    
    private let queue = DispatchQueue(label: "Reporter queue")
    
    
    func filter<T: Filter>(ofType type: T.Type) -> T? {
        for filter in filters {
            if let f = filter as? T {
                return f
            }
        }
        return nil
    }
    
    init(_ rooms: [ChatRoom]) {
        print ("Reporter loading...")
        
        self.rooms = rooms
        
        let blacklistURL = saveDirURL.appendingPathComponent("blacklists.json")
        do {
            blacklistManager = try BlacklistManager(url: blacklistURL)
        } catch {
            handleError(error, "while loading blacklists")
            print("Loading an empty blacklist.")
            blacklistManager = BlacklistManager()
            if FileManager.default.fileExists(atPath: blacklistURL.path) {
                print("Backing up blacklists.json.")
                do {
                    try FileManager.default.moveItem(at: blacklistURL, to: saveDirURL.appendingPathComponent("blacklist.json.bak"))
                } catch {
                    handleError(error, "while backing up the blacklists")
                }
            }
        }
        
        let reportsURL = saveDirURL.appendingPathComponent("reports.json")
        let usernameURL = saveDirURL.appendingPathComponent("blacklisted_users.json")
        do {
            let reportData = try Data(contentsOf: reportsURL)
            guard let reports = try JSONSerialization.jsonObject(with: reportData, options: []) as? [[String:Any]] else {
                throw ReportsLoadingError.ReportsNotArrayOfDictionaries
            }
            
            reportedPosts = try reports.map {
                guard let report = Report(json: $0) else {
                    throw ReportsLoadingError.InvalidReport(report: $0)
                }
                return report
            }
            
        } catch {
            handleError(error, "while loading reports")
            print("Loading an empty report list.")
            if FileManager.default.fileExists(atPath: reportsURL.path) {
                print("Backing up reports.json.")
                do {
                    try FileManager.default.moveItem(at: usernameURL, to: saveDirURL.appendingPathComponent("reports.json.bak"))
                } catch {
                    handleError(error, "while backing up the reports")
                }
            }
        }
        
        do {
            staticDB = try DatabaseConnection("filter_static.sqlite")
        } catch {
            fatalError("Could not load filter_static.sqlite:\n\(error)")
        }
        
        filters = [
            FilterNaiveBayes(reporter: self),
            FilterMisleadingLinks(reporter: self),
            FilterBlacklistedKeyword(reporter: self),
            FilterBlacklistedUsername(reporter: self),
            FilterBlacklistedTag(reporter: self)
        ]
        
        postFetcher = PostFetcher(rooms: rooms, reporter: self, staticDB: staticDB)
    }
    
    func checkPost(_ post: Question, site: Site) throws -> [FilterResult] {
        return try filters.flatMap { try $0.check(post, site: site) }
    }
    
    @discardableResult func checkAndReportPost(_ post: Question, site: Site) throws -> ReportResult {
        let results = try checkPost(post, site: site)
        
        return try report(post: post, site: site, reasons: results)
    }
    
    struct ReportResult {
        enum Status {
            case notBad	//the post was not bad
            case alreadyClosed //the post is already closed
            case alreadyReported //the post was recently reported
            case reported
        }
        var status: Status
        var filterResults: [FilterResult]
    }
    
    enum ReportsLoadingError: Error {
        case ReportsNotArrayOfDictionaries
        case InvalidReport(report: [String:Any])
    }
    
    func saveReports() throws {
        let data = try JSONSerialization.data(
            withJSONObject: reportedPosts.map { $0.json }
        )
        
        try data.write(to: saveDirURL.appendingPathComponent("reports.json"))
    }
    
    enum ReportError: Error {
        case missingSite(id: Int)
    }
    
    ///Reports a post if it has not been recently reported.  Returns either .reported or .alreadyReported.
    func report(post: Question, site: Site, reasons: [FilterResult]) throws -> ReportResult {
        var status: ReportResult.Status = .notBad
        
        queue.sync {
            guard let id = post.id else {
                print("No post ID!")
                status = .notBad
                return
            }
            
            let isManualReport = reasons.contains {
                if case .manuallyReported = $0.type {
                    return true
                } else {
                    return false
                }
            }
            
            if !isManualReport && reportedPosts.lazy.reversed().contains(where: { $0.id == id }) {
                print("Not reporting \(id) because it was recently reported.")
                status = .alreadyReported
                return
            }
            
            if !isManualReport && post.closed_reason != nil {
                print ("Not reporting \(post.id ?? 0) as it is closed.")
                status = .alreadyClosed
                return
            }
            
            var reported = false
            var bayesianDifference: Int?
            var postDetails = "Details unknown."
            
            
            let title = "\(post.title ?? "<no title>")"
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            
            let tags = post.tags ?? []
            postDetails = reasons.map {$0.details ?? "Details unknown."}.joined (separator: ", ")
            
            var messages: [(host: ChatRoom.Host, roomID: Int, messageID: Int)] = []
            
            let sema = DispatchSemaphore(value: 0)
            
            
            for room in rooms {
                //Filter out Bayesian scores which are less than this room's threshold.
                let reasons = reasons.filter {
                    if case .bayesianFilter(let difference) = $0.type {
                        bayesianDifference = difference
                        return difference < room.thresholds[site.id] ?? Int.min
                    }
                    return true
                }
                if reasons.isEmpty {
                    sema.signal()
                    continue
                }
                
                reported = true
                
                let header = reasons.map { $0.header }.joined(separator: ", ")
                let message = "[ [\(botName)](\(stackAppsLink)) ] " +
                    "[tag:\(tags.first ?? "tagless")] \(header) [\(title)](//\(site.domain)/q/\(id)) " +
                    room.notificationString(tags: tags, reasons: reasons)
                
                room.postMessage(message, completion: {message in
                    if let message = message {
                        messages.append((host: room.host, roomID: room.roomID, messageID: message))
                    }
                    sema.signal()
                })
            }
            rooms.forEach { _ in sema.wait() }
            
            
            if reported {
                reportedPosts.append(Report(
                    id: id,
                    when: Date(),
                    difference: bayesianDifference,
                    messages: messages,
                    details: postDetails
                    )
                )
                
                status = .reported
                return
            } else {
                status = .notBad
                return
            }
        }
        
        return ReportResult(status: status, filterResults: reasons)
    }
}
