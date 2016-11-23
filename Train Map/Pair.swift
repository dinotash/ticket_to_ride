//
//  Pair.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Nov 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import CoreData
import MapKit

class Pair: NSManagedObject {
    
    //draw a line between each of the stations
    func routeLine() -> MKPolyline? {
        let fromCoord: CLLocationCoordinate2D? = self.from?.coordinate
        let toCoord: CLLocationCoordinate2D? = self.to?.coordinate
        if (fromCoord == nil) || (toCoord == nil) {
            return nil
        }
        let coOrds: [CLLocationCoordinate2D] = [fromCoord!, toCoord!]
        return MKPolyline(coordinates: coOrds, count: coOrds.count)
    }
}
