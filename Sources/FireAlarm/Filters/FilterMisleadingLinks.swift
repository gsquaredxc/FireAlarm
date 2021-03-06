//
//  FilterMisleadingLinks.swift
//  FireAlarm
//
//  Created by Ashish Ahuja on 23/04/17.
//
//

import Foundation
import SwiftChatSE
import SwiftStack
import Dispatch

class FilterMisleadingLinks: Filter {
    required init (reporter: Reporter) {}
    
    func check(_ post: Question, site: Site) -> FilterResult? {
        do {
            let regex = try NSRegularExpression(pattern:
                "<a href=\"([^\"]*)\" rel=\"nofollow(?: noreferrer)?\">\\s*([^<\\s]*)(?=\\s*</a>)", options: []
            )
            
            guard let body = post.body else {
                print("No body for \(post.id.map { String($0) } ?? "<no ID>")!")
                return nil
            }
            
            #if os(Linux)
                let nsString = body._bridgeToObjectiveC()
            #else
                let nsString = body as NSString
            #endif
            for match in regex.matches(in: body, options: [], range: NSMakeRange(0, nsString.length)) {
                
                
                    let linkString = nsString.substring(with: match.range(at: 1))
                    let textString = nsString.substring(with: match.range(at: 2))
                guard
                    let link = URL(string: linkString),
                    let text = URL(string: textString),
                    let linkHost = link.host?.lowercased(),
                    let textHost = text.host?.lowercased() else {
                        continue
                }
                
                
                if (!textHost.isEmpty &&
                    textHost != linkHost &&
                    !linkHost.contains("rads.stackoverflow.com") &&
                    "www." + textHost != linkHost &&
                    "www." + linkHost != textHost &&
                    linkHost.contains(".") &&
                    textHost.contains(".") &&
                    !linkHost.trimmingCharacters(in: .whitespaces).contains(" ") &&
                    !textHost.trimmingCharacters(in: .whitespaces).contains(" ") &&
                    !linkHost.contains("//http") &&
                    !textHost.contains("//http")) {
                    
					return FilterResult(
						type: .customFilter(filter: self),
						header: "Misleading link",
						details: "Link appears to go to `\(textHost)` but actually goes to `\(linkHost)`"
					)
                }
                
                
            }
            return nil
            
        } catch {
            handleError(error, "while checking for misleading links")
            return nil
        }
	}
	
    func save() throws {
		
	}
}
