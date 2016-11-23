//
//  Station+CoreDataProperties.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Station {

    @NSManaged var cate: NSNumber?
    @NSManaged var change_time: NSNumber?
    @NSManaged var crs_main: String?
    @NSManaged var crs_subsidiary: String?
    @NSManaged var easting: NSNumber?
    @NSManaged var name: String?
    @NSManaged var northing: NSNumber?
    @NSManaged var alias: NSSet?
    @NSManaged var dataset: NSManagedObject?
    @NSManaged var groups: NSSet?
    @NSManaged var linksFrom: NSSet?
    @NSManaged var linksTo: NSSet?
    @NSManaged var routeEntries: NSSet?
    @NSManaged var tiploc: NSSet?
    @NSManaged var pairTo: NSManagedObject?
    @NSManaged var pairFrom: NSManagedObject?
}
