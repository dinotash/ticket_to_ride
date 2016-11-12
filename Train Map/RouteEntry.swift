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

// Insert code here to add functionality to your managed object subclass
    
    //return in HHMM the earliest time for any of the entry's time fields
    func earliest_time() -> String {
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
        
        //return the smallest -> i.e. alphabetical order
        return times.min()!
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
        let lhs_time = lhs.earliest_time()
        let rhs_time = rhs.earliest_time()
        
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
