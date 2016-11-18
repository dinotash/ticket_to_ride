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
    
    var coordinate: CLLocationCoordinate2D {
        //if we've already worked it out, give it
        if (self.mapPoint != nil) {
            return self.mapPoint!
        }
        else {
            //work it out -- maths thanks to here (converted from javascript)
            //https://github.com/chrisveness/geodesy/blob/master/osgridref.js

            let a = 6377563.396
            let b = 6356256.909                                // Airy 1830 major & minor semi-axes
            let F0 = 0.9996012717                              // NatGrid scale factor on central meridian
            let φ0 = (49.0 / 180.0) * .pi
            let λ0 = (-2.0 / 180.0) * .pi                      // NatGrid true origin is 49°N,2°W
            let N0 = -100000.0
            let E0 = 400000.0                                  // northing & easting of true origin, metres
            let e2 = 1.0 - (b*b)/(a*a)                         // eccentricity squared
            let n = (a-b)/(a+b)
            let n2 = n*n
            let n3 = n*n*n                                     // n, n², n³
            var φ = φ0
            var M = 0.0
            while (Double(self.northing!) - N0 - M >= 0.00001) {        // ie until < 0.01mm
                φ = (Double(self.northing!) - N0 - M)/(a*F0) + φ
                let Ma = (1 + n + (5/4)*n2 + (5/4)*n3) * (φ-φ0)
                let Mb = (3*n + 3*n*n + (21/8)*n3) * sin(φ-φ0) * cos(φ+φ0)
                let Mc = ((15/8)*n2 + (15/8)*n3) * sin(2*(φ-φ0)) * cos(2*(φ+φ0))
                let Md = (35/24)*n3 * sin(3*(φ-φ0)) * cos(3*(φ+φ0));
                M = b * F0 * (Ma - Mb + Mc - Md);              // meridional arc
            }

            let cosφ = cos(φ)
            let sinφ = sin(φ)
            let ν = a*F0/sqrt(1-e2*sinφ*sinφ)                  // nu = transverse radius of curvature
            let ρ = a*F0*(1-e2)/pow(1-e2*sinφ*sinφ, 1.5)       // rho = meridional radius of curvature
            let η2 = ν/ρ-1;                                    // eta = ?

            let tanφ = tan(φ);
            let tan2φ = tanφ*tanφ, tan4φ = tan2φ*tan2φ, tan6φ = tan4φ*tan2φ;
            let secφ = 1/cosφ;
            let ν3 = ν*ν*ν, ν5 = ν3*ν*ν, ν7 = ν5*ν*ν;
            let VII = tanφ/(2*ρ*ν);
            let VIII = tanφ/(24*ρ*ν3)*(5+3*tan2φ+η2-9*tan2φ*η2);
            let IX = tanφ/(720*ρ*ν5)*(61+90*tan2φ+45*tan4φ);
            let X = secφ/ν;
            let XI = secφ/(6*ν3)*(ν/ρ+2*tan2φ);
            let XII = secφ/(120*ν5)*(5+28*tan2φ+24*tan4φ);
            let XIIA = secφ/(5040*ν7)*(61+662*tan2φ+1320*tan4φ+720*tan6φ);

            let dE = Double(self.easting!)-E0
            let dE2 = dE*dE
            let dE3 = dE2*dE
            let dE4 = dE2*dE2
            let dE5 = dE3*dE2
            let dE6 = dE4*dE2
            let dE7 = dE5*dE2
            φ = φ - VII*dE2 + VIII*dE4 - IX*dE6;
            let λ = λ0 + X*dE - XI*dE3 + XII*dE5 - XIIA*dE7

            //convert to latitude/longitude
            let lat = (φ / .pi) * 180.0
            let long = (λ / .pi) * 180.0
            self.mapPoint = CLLocationCoordinate2DMake(lat, long) // save the result!
            return self.mapPoint!
        }
    }
    
    var title: String? {
        return self.name
    }
    
    var subtitle: String? {
        return self.name
    }
}
