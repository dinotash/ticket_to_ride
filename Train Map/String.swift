//
//  String.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 25 Jul 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func >= <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l >= r
  default:
    return !(lhs < rhs)
  }
}


extension String {
    
    //method to take a substring in an easy manner
    func substring(_ start: Int, end: Int, trim: Bool=true, trimDashes: Bool=false) -> String {
        let substringStart = self.characters.index(self.startIndex, offsetBy: start)
        
        //if end is too long, wrap to end of string, otherwise use real value
        let endLimit = self.characters.index(self.endIndex, offsetBy: -1, limitedBy: self.startIndex)
        let substringEnd = self.characters.index(self.startIndex, offsetBy: end, limitedBy: endLimit!)
        
        var newSubstring = self[substringStart...substringEnd!]
        
        if trimDashes { // to cope with ZTR file
            newSubstring = newSubstring.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        
        if (trim) {
            return newSubstring.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        else {
            return newSubstring
        }
    }
    
    func formatName() -> String {
        var newName = self.capitalized(with: Locale(identifier: "en_GB"))
        newName = newName.replacingOccurrences(of: "<Cie>", with: "<CIE>")
        newName = newName.replacingOccurrences(of: "<Lul>", with: "<LUL>")
        newName = newName.replacingOccurrences(of: "<Nir>", with: "<NIR>")
        newName = newName.replacingOccurrences(of: "<Ns>", with: "<NS>")
        newName = newName.replacingOccurrences(of: "<Evr>", with: "<EVR>")
        return newName
    }
    
    //convert from yymmdd format to a date
    func yymmddDate() -> Date? {
        if (self.characters.count == 6) { //
            if (Int(self) != nil) { //check it's numeric
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd"
                
                //deal with case for open ended services, treat as running until year 3000
                if (self == "99999") {
                    return Date.distantFuture
                }
                    //otherwise, check the century and process as expected
                else {
                    let shortYear = self.substring(0, end: 1)
                    let shortYearNum = Int(shortYear)
                    if (shortYearNum >= 60) { //60-99 assumed to be 1960-1999
                        let century = "19"
                        let fullDate = century + self
                        return dateFormatter.date(from: fullDate)
                    }
                    else {
                        let century = "20" //00-59 assumed to be 2000-2059
                        let fullDate = century + self
                        return dateFormatter.date(from: fullDate)
                    }
                }
            }
        }
        return nil //didn't have a valid date
    }
    
    func hhmmTime() -> (hour: Int, minute: Int)? {
        if (self != "") {
            if (self.characters.count == 4) {
                if (Int(self) != nil) {
                    let hour = Int(self.substring(0, end: 1))!
                    let minute = Int(self.substring(2, end: 3))!
                    return (hour, minute)
                }
            }
        }
        return nil
    }
    
    //convert two numbers to a string after adding leading zeros
    static func timeHHMM(_ hour: NSNumber?, minute: NSNumber?) -> String {
        if (hour == nil) || (minute == nil) {
            return ""
        }
        
        let hour_string = String(format: "%02d", hour!.intValue)
        let minute_string = String(format: "%02d", minute!.intValue)
        let combined_string = hour_string + minute_string
        if (combined_string == "0000") {
            return "" //blank string
        }
        else {
            return combined_string
        }
    }
}
