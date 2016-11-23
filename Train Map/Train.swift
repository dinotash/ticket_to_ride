//
//  Train.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import CoreData
import MapKit

class Train: NSManagedObject {

    //find out where this train is going
    func destination() -> String {
        let lastEntry: RouteEntry = self.routeEntries!.lastObject as! RouteEntry
        let lastStation: Station = lastEntry.station!
        return lastStation.name!
    }
    
    //where did it come from?
    func origin() -> String {
        let firstEntry: RouteEntry = self.routeEntries!.firstObject as! RouteEntry
        let firstStation: Station = firstEntry.station!
        return firstStation.name!
    }
    
}
