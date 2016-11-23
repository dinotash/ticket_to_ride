//
//  Pair+CoreDataProperties.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Nov 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import CoreData

extension Pair {
    
    @NSManaged var count: NSNumber?
    @NSManaged var dataset: NSManagedObject?
    @NSManaged var from: Station?
    @NSManaged var to: Station?
    @NSManaged var fromRouteEntries: NSSet?
    @NSManaged var toRouteEntriess: NSSet?
}
