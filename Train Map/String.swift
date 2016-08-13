//
//  String.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 25 Jul 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

extension String {
    
    //method to take a substring in an easy manner
    func substring(start: Int, end: Int, trim: Bool=true, trimDashes: Bool=false) -> String {
        let substringStart = self.startIndex.advancedBy(start)
        
        //if end is too long, wrap to end of string, otherwise use real value
        let endLimit = self.endIndex.advancedBy(-1, limit: self.startIndex)
        let substringEnd = self.startIndex.advancedBy(end, limit: endLimit)
        
        var newSubstring = self[substringStart...substringEnd]
        
        if trimDashes { // to cope with ZTR file
            newSubstring = newSubstring.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "-"))
        }
        
        if (trim) {
            return newSubstring.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        }
        else {
            return newSubstring
        }
    }
    
    func formatName() -> String {
        var newName = self.capitalizedStringWithLocale(NSLocale(localeIdentifier: "en_GB"))
        newName = newName.stringByReplacingOccurrencesOfString("<Cie>", withString: "<CIE>")
        newName = newName.stringByReplacingOccurrencesOfString("<Lul>", withString: "<LUL>")
        newName = newName.stringByReplacingOccurrencesOfString("<Nir>", withString: "<NIR>")
        newName = newName.stringByReplacingOccurrencesOfString("<Ns>", withString: "<NS>")
        newName = newName.stringByReplacingOccurrencesOfString("<Evr>", withString: "<EVR>")
        return newName
    }
    
    //convert from yymmdd format to a date
    func yymmddDate() -> NSDate? {
        if (self.characters.count == 6) { //
            if (Int(self) != nil) { //check it's numeric
                let dateFormatter = NSDateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd"
                
                //deal with case for open ended services, treat as running until year 3000
                if (self == "99999") {
                    return NSDate.distantFuture()
                }
                    //otherwise, check the century and process as expected
                else {
                    let shortYear = self.substring(0, end: 1)
                    let shortYearNum = Int(shortYear)
                    if (shortYearNum >= 60) { //60-99 assumed to be 1960-1999
                        let century = "19"
                        let fullDate = century + self
                        return dateFormatter.dateFromString(fullDate)
                    }
                    else {
                        let century = "20" //00-59 assumed to be 2000-2059
                        let fullDate = century + self
                        return dateFormatter.dateFromString(fullDate)
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
}