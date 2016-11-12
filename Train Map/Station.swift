//
//  Station.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import CoreData


class Station: NSManagedObject {

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
}
