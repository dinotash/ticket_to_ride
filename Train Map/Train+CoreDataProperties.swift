//
//  Train+CoreDataProperties.swift
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

extension Train {

    @NSManaged var end: Date?
    @NSManaged var id: String?
    @NSManaged var identity: String?
    @NSManaged var runsOnEnglishBankHolidays: NSNumber?
    @NSManaged var runsOnScottishBankHolidays: NSNumber?
    @NSManaged var speed: NSNumber?
    @NSManaged var start: Date?
    @NSManaged var uid: String?
    @NSManaged var atoc: NSManagedObject?
    @NSManaged var category: NSManagedObject?
    @NSManaged var catering: NSSet?
    @NSManaged var class_type: NSManagedObject?
    @NSManaged var dataset: NSManagedObject?
    @NSManaged var power: NSManagedObject?
    @NSManaged var reservations: NSManagedObject?
    @NSManaged var routeEntries: NSOrderedSet?
    @NSManaged var runsOn: NSSet?
    @NSManaged var sleeper: NSManagedObject?

}
