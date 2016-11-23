//
//  Date.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 11 Sep 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

extension Date {
    
    //return the date of Easter (for Roman Catholics)
    //https://gist.github.com/duedal/2eabcede718c69670102
    static func easter(_ Y : Int) -> Date {
        let a: Int = Y % 19
        let b: Int = Int(floor(Double(Y) / 100))
        let c: Int = Y % 100
        let d: Int = Int(floor(Double(b) / 4))
        let e: Int = b % 4
        let f: Int = Int(floor(Double(b+8) / 25))
        let g: Int = Int(floor(Double(b-f+1) / 3))
        let h: Int = (19*a + b - d - g + 15) % 30
        let i: Int = Int(floor(Double(c) / 4))
        let k: Int = c % 4
        let L: Int = (32 + 2*e + 2*i - h - k) % 7
        let m: Int = Int(floor(Double(a + 11*h + 22*L) / 451))
        var components: DateComponents = DateComponents()
        components.year = Y
        components.month = Int(floor(Double(h + L - 7*m + 114) / 31))
        components.day = ((h + L - 7*m + 114) % 31) + 1
        (components as NSDateComponents).timeZone = TimeZone(secondsFromGMT: 0)
        let cal: Calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        return cal.date(from: components)!
    }
    
    //is it a bank Holiday in England or Scotland?
    func bankHoliday() -> (Bool, Bool) {
        //bank holidays are:
        //New Year's Day --> 1 January -- Both
        //2 January --> Scotland
        //Good Friday --> March or April --> Both
        //Easter Monday --> March or April --> England
        //May Day --> first Monday in May --> Both
        //last Monday in May --> Both
        //first Monday in August --> Scotland
        //last Monday in August --> England
        //St Andrew's Day --> 30 November --> Scotland
        //Christmas Day --> 25 December --> Both
        //Boxing Day --> 26 December --> Both

        //get the date components we need
        let calendar: Calendar = Calendar.current
        let components: DateComponents = calendar.dateComponents([.day, .month, .year, .weekday], from: self)
        let day: Int? = components.day
        let month: Int? = components.month
        let year: Int? = components.year
        let weekday: Int? = components.weekday
        
        //date formatter for checking other dates
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyy-M-d"

        //bank holidays are never at the weekend
        if (weekday == 1) || (weekday == 7) {
            return (false, false)
        }
        
        //January
        if month == 1 {
            //if the first is at the weekend, then the days off move along into the week
            var days_to_add = 0
            let firstWeekday: Int = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-1-1")!)
            if (firstWeekday == 1) {
                days_to_add = 1
            }
            if (firstWeekday == 7) {
                days_to_add = 2
            }
            
            //the 1st is a bank holiday in both countries
            if day == (1 + days_to_add) {
                return (true, true)
            }
            //the 2nd is a bank holiday in Scotland only
            if day == (2 + days_to_add) {
                return (false, true)
            }
        }
        
        //March or April -- Gregorian Easter can be between 22 March and 25 April
        if (month == 3) || (month == 4) {
            //get date of Easter Sunday -- day after or two days before
            let easterDate: DateComponents = calendar.dateComponents([.day, .month], from:Date.easter(year!))
            let easterDay: Int? = easterDate.day
            let easterMonth: Int? = easterDate.month
            
            //deal with month-crossing by exception
            //if 31 March is Easter Sunday, then Easter Monday is 1 April
            if (easterDay == 31) {
                if (month == 4) && (day == 1) {
                    return (true, false) //England only
                }
            }
            
            //if Easter Sunday is 1 April, then Good Friday was 30 March
            if (easterDay == 1) {
                if (month == 3) && (day == 30) {
                    return (true, true) //Both countries observe Good Friday
                }
            }
            //if Easter Sunday is 2 April, then Good Friday was 31 March
            if (easterDay == 2) {
                if (month == 3) && (day == 31) {
                    return (true, true)
                }
            }
            
            //otherwise, just get on with it
            if (month == easterMonth) {
                //Easter Monday
                if (day! == easterDay! + 1) {
                    return (true, false) //England only
                }
                //Good Friday
                if (day! == easterDay! - 2) {
                    return (true, true) //Both countries
                }
            }
        }
        
        //May
        if (month == 5) {
            //find out the first Monday based on weekday of 1 May
            let firstWeekday: Int = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-5-1")!)
            let days_to_add: Int = (2 - firstWeekday) % 7 // how long to get to the first monday?
            if day == (1 + days_to_add) {
                return (true, true)
            }
            
            //similar logic for the last Monday in May
            let lastWeekday: Int = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-5-31")!)
            let days_to_subtract: Int = (lastWeekday - 2) % 7
            if (day == (31 - days_to_subtract)) {
                return (true, true)
            }
        }
        
        //August
        if (month == 8) {
            //find out the first Monday based on weekday of 1 August
            let firstWeekday: Int = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-8-1")!)
            let days_to_add: Int = (2 - firstWeekday) % 7 // how long to get to the first monday?
            if day == (1 + days_to_add) {
                return (false, true) //Scotland only
            }
            
            //similar logic for last Monday in August
            let lastWeekday: Int = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-8-31")!)
            let days_to_subtract: Int = (lastWeekday - 2) % 7
            if (day == (31 - days_to_subtract)) {
                return (true, false) //England only
            }
        }
        
        //November
        if (month == 11) {
            //find out weekday of St Andrew's Day (30 November) -- Normally on the day itself, unless it's at the weekend
            let andrewsWeekday: Int? = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-11-30")!)
            if (andrewsWeekday != 1) && (andrewsWeekday != 2) && (day == 30) {
                return (false, true) //Scotland only
            }
        }

        //December
        if (month == 12) {
            //if the 1st or 2nd is a Monday, then it's a spillover from St Andrew's Day being at the weekend
            if (day == 1) || (day == 2) {
                let andrewsWeekday: Int? = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-12-" + String(day!))!)
                if (andrewsWeekday == 2) {
                    return (false, true) //Scotland only
                }
            }
            
            //check if Christmas is at the weekend
            let christmasWeekday: Int? = calendar.component(.weekday, from: formatter.date(from: String(year!) + "-12-25")!)
            var days_to_add: Int = 0
            if (christmasWeekday == 1) {
                days_to_add = 1 //sunday moves it on one day
            }
            if (christmasWeekday == 7) {
                days_to_add = 2 //saturday moves it on two days
            }
            if day == (25 + days_to_add) {
                return (true, true) //christmas day
            }
            if day == (26 + days_to_add) {
                return (true, true) //boxing day
            }
        }
        
        //default: not a bank holiday in either country
        return (false, false)

    }

    //nice and easy does it
    func weekday() -> Int {
        let calendar: Calendar = Calendar.current
        return calendar.dateComponents([.weekday], from: self).weekday!
        //return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day_num]
    }
}
