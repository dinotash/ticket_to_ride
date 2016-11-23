//
//  RouteEntry+CoreDataProperties.swift
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

extension RouteEntry {

    @NSManaged var line: String?
    @NSManaged var platform: String?
    @NSManaged var public_arrival_hour: NSNumber?
    @NSManaged var public_arrival_minute: NSNumber?
    @NSManaged var public_departure_hour: NSNumber?
    @NSManaged var public_departure_minute: NSNumber?
    @NSManaged var scheduled_arrival_hour: NSNumber?
    @NSManaged var scheduled_arrival_minute: NSNumber?
    @NSManaged var scheduled_departure_hour: NSNumber?
    @NSManaged var scheduled_departure_minute: NSNumber?
    @NSManaged var scheduled_pass_hour: NSNumber?
    @NSManaged var scheduled_pass_minute: NSNumber?
    @NSManaged var activities: NSSet?
    @NSManaged var dataset: NSManagedObject?
    @NSManaged var station: Station?
    @NSManaged var train: Train?
    @NSManaged var next: RouteEntry?
    @NSManaged var prev: RouteEntry?
    @NSManaged var nextPair: NSManagedObject?
    @NSManaged var prevPair: NSManagedObject?
}
