//
//  RouteEntry.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import CoreData


class RouteEntry: NSManagedObject {
    
    static func time_number(hour: NSNumber?, minute: NSNumber?) -> Int {
        //try to convert to integers if we can
        var h: Int = -1
        var m: Int = 0
        
        if (hour != nil) {
            h = hour!.intValue
        }
        if (minute != nil) {
            m = minute!.intValue
        }
        
        return (100 * h) + m
    }
    
    //return integer value for earliest/latest - more flexible/quicker than strings
    func end_times() -> (Int, Int) {
        let arrival = RouteEntry.time_number(hour: scheduled_arrival_hour, minute: scheduled_arrival_minute)
        let departure = RouteEntry.time_number(hour: scheduled_departure_hour, minute: scheduled_departure_minute)
        let pass = RouteEntry.time_number(hour: scheduled_pass_hour, minute: scheduled_pass_minute)
        
        //collect the non-negative (i.e. not missing) times
        var times = [Int]()
        if arrival >= 0 {
            times.append(arrival)
        }
        if departure >= 0 {
            times.append(departure)
        }
        if pass >= 0 {
            times.append(pass)
        }
        
        return (times.min()!, times.max()!)
    }
    
    func earliest_time() -> Int {
        return self.end_times().0
    }
    
    func latest_time() -> Int {
        return self.end_times().1
    }
    
    
    //return in HHMM the earliest time for any of the entry's time fields
    func end_times_string() -> (String, String) {
        let arrival = String.timeHHMM(scheduled_arrival_hour, minute: scheduled_arrival_minute)
        let departure = String.timeHHMM(scheduled_departure_hour, minute: scheduled_departure_minute)
        let pass = String.timeHHMM(scheduled_pass_hour, minute: scheduled_pass_minute)
        
        //collect the non-nil strings -> at least one will exist
        var times = [String]()
        if arrival.characters.count > 0 {
            times.append(arrival)
        }
        if (departure.characters.count) > 0 {
            times.append(departure)
        }
        if (pass.characters.count) > 0 {
            times.append(pass)
        }
        
        //return the smallest and biggest -> i.e. alphabetical order
        return (times.min()!, times.max()!)
    }
    
    func earliest_time_string() -> String {
        return self.end_times_string().0
    }
    
    func latest_time_string() -> String {
        return self.end_times_string().1
    }
}

//make it possible to compare based on times
extension RouteEntry: Comparable {

    static func == (lhs: RouteEntry, rhs: RouteEntry) -> Bool {
        //first off check they have the same train and station
        if (lhs.station != rhs.station) || (lhs.train != rhs.train) {
            return false
        }
        
        //check all the fields to see if they're all the same
        let fields = NSEntityDescription.entity(forEntityName: lhs.className, in: lhs.managedObjectContext!)!.attributeKeys
        let lhs_fields = lhs.dictionaryWithValues(forKeys: fields)
        let rhs_fields = rhs.dictionaryWithValues(forKeys: fields)
        
        //check every field in turn
        for field in fields {
            if let lhs_value = lhs_fields[field] as? NSNumber {
                let rhs_value = rhs_fields[field] as! NSNumber
                if (lhs_value != rhs_value) {
                    return false
                }
            }
            
            if let lhs_value = lhs_fields[field] as? String {
                let rhs_value = rhs_fields[field] as! String
                if (lhs_value != rhs_value) {
                    return false
                }
            }
        }
        return true
    }
    
    static func < (lhs: RouteEntry, rhs: RouteEntry) -> Bool {
        // order -> by hour then minute in each one's earliest time
        let lhs_time = lhs.earliest_time_string()
        let rhs_time = rhs.earliest_time_string()
        
        if lhs_time < rhs_time {
            return true
        }
        //alphabetical tie breaker
        if (lhs_time == rhs_time) && (lhs.train!.destination() < rhs.train!.destination()) {
            return true
        }
        else {
            return false
        }
    }
}
