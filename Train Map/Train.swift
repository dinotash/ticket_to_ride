//
//  Train.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import CoreData


class Train: NSManagedObject {
    
    //keep track of where we are
    var startRouteIndex: Int?
    var endRouteIndex: Int?
    var routeIndexProgress: Double?

    //find out where this train is going
    func destination() -> String {
        let lastEntry = self.routeEntries!.lastObject as! RouteEntry
        let lastStation = lastEntry.station!
        return lastStation.name!
    }
    
    //where did it come from?
    func origin() -> String {
        let firstEntry = self.routeEntries!.firstObject as! RouteEntry
        let firstStation = firstEntry.station!
        return firstStation.name!
    }
    
    //find where it is at a given time by binary search
    var prevStation: RouteEntry?
    var nextStation: RouteEntry?
    
    func location(time: Int) -> (RouteEntry?, RouteEntry?) {
        //check it's a valid time string
        if (time < 0) || (time / 100 > 23) || (time % 100 > 59) {
            return (nil, nil)
        }
        
        var l = 0
        var u = self.routeEntries!.count - 1
        
        while (l < u) {
            let m = (u - l) / 2
            let middle = self.routeEntries!.object(at: m) as! RouteEntry
            let middleTimes = middle.end_times()
            let middleStart = middleTimes.0
            let middleEnd = middleTimes.1
            
            //sat at a station -> one legged -> between arriving and departing
            if (middleStart <= time && middleEnd >= time) {
                return (middle, nil)
            }
            
            //too early - keep looking backwards
            if time < middleStart {
                //check if we are en route from previous
                let p = m - 1
                if p >= 0 {
                    let prev = self.routeEntries!.object(at: p) as! RouteEntry
                    if time >= prev.latest_time() {
                        return (prev, middle)
                    }
                }
                u = p //need to look further back - restrict binary search
            }
            
            //too late - check if we are in this pair, otherwise search on
            if time > middleEnd {
                let n = m + 1
                if n < self.routeEntries!.count {
                    let next = self.routeEntries!.object(at: n) as! RouteEntry
                    if time <= next.earliest_time() {
                        return (middle, next)
                    }
                }
                l = n
            }
        }
        return (nil, nil) //didn't find it
    }
    
    func move() {
        //
    }
}
