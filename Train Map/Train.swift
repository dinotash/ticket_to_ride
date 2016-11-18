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
    
    //draw a line between each of the stations
    func routeLine() -> MKPolyline? {
        var coOrds: [CLLocationCoordinate2D] = []
        for routeEntry in self.routeEntries! {
            let re = routeEntry as! RouteEntry
            if (re.station!.northing! == 0) || (re.station!.easting! == 0) {
                return nil //don't draw line if any stations are off the map
            }
            coOrds.append(re.station!.coordinate)
        }
        return MKPolyline(coordinates: coOrds, count: coOrds.count)
    }
}
