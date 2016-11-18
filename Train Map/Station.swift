//
//  Station.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import CoreData
import MapKit

class Station: NSManagedObject, MKAnnotation {
    
    //calculate locations by reference to Manchester Piccadilly station
    static let manchesterPiccadilly = CLLocationCoordinate2DMake(53.477, -2.23)
    static let manchesterPiccadillyNorthing = 63978
    static let manchesterPiccadillyEasting = 13849

    
    var mapPoint: CLLocationCoordinate2D?

    func dateRange() -> (Date, Date) {
        var min_date = Date.distantFuture
        var max_date = Date.distantPast
        
        for e in self.routeEntries! {
            let start = (e as! RouteEntry).train!.start!
            let end = (e as! RouteEntry).train!.end!
            
            if start < min_date {
                min_date = start
            }
            if end > max_date {
                max_date = end - 1
            }
        }
        return (min_date, max_date)
    }
    
    func locationWithBearing(bearing:Double, distanceMeters:Double, origin:CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let distRadians = distanceMeters / (6372797.6) // earth radius in meters
        
        let lat1 = origin.latitude * .pi / 180.0
        let lon1 = origin.longitude * .pi / 180.0
        
        let lat2 = asin(sin(lat1) * cos(distRadians) + cos(lat1) * sin(distRadians) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(distRadians) * cos(lat1), cos(distRadians) - sin(lat1) * sin(lat2))
        
        return CLLocationCoordinate2D(latitude: lat2 * 180.0 / .pi, longitude: lon2 * 180.0 / .pi)
    }
    
    var coordinate: CLLocationCoordinate2D {
        //if we've already worked it out, give it
        if (self.mapPoint != nil) {
            return self.mapPoint!
        }
        else {
            //find distance and bearing from Manchester Piccadilly reference point
            let northDiff = -100.0 * Double(Station.manchesterPiccadillyNorthing - (self.northing! as Int))
            let eastDiff = 100.0 * Double(Station.manchesterPiccadillyEasting - (self.easting! as Int))
            let crowDist = sqrt((northDiff * northDiff) + (eastDiff * eastDiff)) //absolute distance
            let bearing = atan2(northDiff, eastDiff) - (.pi / 2.0) //angle from horizontal, rotated so 0 = north
            self.mapPoint = locationWithBearing(bearing: bearing, distanceMeters: crowDist, origin: Station.manchesterPiccadilly)
            return self.mapPoint!
        }
    }
    
    var title: String? {
        if self.name == "Llanfairpwll" {
            return "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch"
        }
        return self.name
    }
    
    var subtitle: String? {
        return nil
    }
}
