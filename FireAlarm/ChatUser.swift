//
//  ChatUser.swift
//  FireAlarm
//
//  Created by Jonathan Keller on 8/28/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Cocoa

class ChatUser: CustomStringConvertible {
    
    let id: Int
    
    private var _name: String?
    private var _isMod: Bool?
    private var _isRO: Bool?
    
    var name: String {
        get {
            if let n = _name {
                return n
            }
            else {
                room.lookupUserInformation()
                return _name ?? "<unkown user \(id)>"
            }
        }
        set {
            _name = newValue
        }
    }
    
    var isMod: Bool {
        get {
            if let i = _isMod {
                return i
            }
            else {
                room.lookupUserInformation()
                return _isMod ?? false
            }
        }
        set {
            _isMod = newValue
        }
    }
    
    var isRO: Bool {
        get {
            if let i = _isRO {
                return i
            }
            else {
                room.lookupUserInformation()
                return _isRO ?? false
            }
        }
        set {
            _isRO = newValue
        }
    }
    
    var description: String {
        return name
    }
    
    
    let room: ChatRoom
    
    init(room: ChatRoom, id: Int, name: String? = nil) {
        self.room = room
        self.id = id
        _name = name
    }
}