//
//  ImportOperations.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 5 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

//https://www.raywenderlich.com/76341/use-nsoperation-nsoperationqueue-swift

//queue of imports to be done
class PendingOperations {
    lazy var importsInProgress: [Operation] = [Operation]()
    lazy var importQueue: OperationQueue = {
        var queue: OperationQueue = OperationQueue()
        queue.name = "Import queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
}

//where we actually do the import
class ttisImporter: Operation {
    
    //keep track of variables set outside the operation -> passed in on init()
    let MOC: NSManagedObjectContext //Need a separate managed object context for the separate thread
    let chosenFile: URL //file we selected
    let progressViewController: ImportProgressViewController?
    let updateLimit: Int = 10000 //how many iterations before updating progress bar
    var dataSet: NSManagedObject?
    
    //have a variable starting point so we can keep track of import / pick up later on
    var msnProgress: Int = 0 //default is to start at the beginning
    var mcaProgress: Int = 0
    var ztrProgress: Int = 0
    var alfProgress: Int = 0
    var importCount: Int = 0
    var totalCount: Int = 0
    
    //keep track of each way of looking up cached objects, in preference order
    let entityKeys: [String : [String]] = [
        "Weekday": ["number"],
        "LinkMode": ["string"],
        "Station": ["crs_main", "crs_subsidiary", "name"],
        "ATOC": ["code"],
        "Activity": ["code"],
        "Category": ["code"],
        "Catering": ["code"],
        "Class": ["code"],
        "Power": ["code"],
        "Reservation": ["code"],
        "Sleeper": ["code"],
        "Tiploc": ["code"],
    ]
    
    //cache results for some of the codes we will want to fetch later
    var objectCache: [Duplet<String, String> : NSManagedObject] = [:] //(entityType, ID) : Object
    let blankObject: NSManagedObject
    var pairCache: [Duplet<Station, Station>: Pair] = [:]
    
    //initialize the variables used within the thread
    init(chosenFile: URL, progressViewController: ImportProgressViewController?) {
        
        //create MOC from scratch
        let coordinator: NSPersistentStoreCoordinator = (NSApplication.shared().delegate as! AppDelegate).persistentStoreCoordinator
        self.MOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        self.MOC.persistentStoreCoordinator = coordinator
        self.MOC.undoManager = nil //makes it go faster, apparently
        let blankDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Blank", in: self.MOC)
        self.blankObject = NSManagedObject(entity: blankDescription!, insertInto: self.MOC) //use this as a placeholder
        
        //pass along other variables for later use
        self.progressViewController = progressViewController
        self.chosenFile = chosenFile
        super.init()
        
        self.qualityOfService = .utility //don't need to hold things up immediately for this
    }
    
    fileprivate func saveImport(_ after: String) {
        // Performs the save action for the import thread, which is to send the save: message to the thread's managed object context. Any encountered errors are presented to the user.
        if !self.MOC.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if self.MOC.hasChanges {
            do {
                try self.MOC.save()
                print("Saved imported data after loading " + after)
            } catch {
                let nserror: NSError = error as NSError
                print(nserror)
            }
        }
    }
    
    //when loading files, check each expected file exists
    fileprivate func fileExists(_ expectedFilePath: URL) -> Bool {
        return (FileManager.default.fileExists(atPath: expectedFilePath.relativePath))
    }
    
    //convenience method used in loadConstants() to actually create the objects
    fileprivate func createObjectsForConstantCodes(_ codes: [String: String], entityName: String) {
        let entityFetch: NSFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        do {
            if (try self.MOC.count(for: entityFetch) == 0) { //add only if not already there
                let newEntityDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: entityName, in: self.MOC)
                for (key, value) in codes {
                    let newEntity: NSManagedObject = NSManagedObject(entity: newEntityDescription!, insertInto: self.MOC)
                    newEntity.setValue(key, forKey: "code")
                    newEntity.setValue(value, forKey: "string")
                    let cacheKey: Duplet<String, String> = Duplet<String, String>(entityName, key)
                    self.objectCache[cacheKey] = newEntity
                }
            }
        }
        catch {
            let nserror: NSError = error as NSError
            print(nserror)
        }
    }
    
    //function to take a file and read it in line by line, giving an array at the end
    fileprivate func readFileLines(_ path: URL) -> [String] {
        do {
            //load the data, split into lines
            let fileData: String = try String(contentsOfFile: path.relativePath, encoding: String.Encoding.utf8)
            let fileLines: [String] = fileData.components(separatedBy: "\n")
            return fileLines
        }
        catch {
            DispatchQueue.main.async(execute: {
                let alert: NSAlert = NSAlert();
                alert.alertStyle = NSAlertStyle.warning
                alert.messageText = "Unable to load data from file";
                alert.informativeText = "Could not load data from file " + path.relativePath
                alert.runModal();
            })
            return [] //stop without doing anything
        }
    }
    
    //convenience method to find an object if cached, and fetch it if not
    fileprivate func fetchKeyFromCache(_ key: Duplet<String, String>) -> NSManagedObject? {
        if let obj: NSManagedObject = self.objectCache[key] { //check it's in the array
            if obj == self.blankObject {
                return nil //if we know we have nothing
            }
            else {
                return self.objectCache[key]
            }
        }
        else {
            //else have to go and fetch it
            let entityType: String = key.one
            let keyValue: String = key.two
            if let keyNames: [String] = self.entityKeys[entityType] {
                for keyName in keyNames {
                    let newFetch: NSFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityType)
                    newFetch.predicate = NSPredicate(format: keyName + " == %@", keyValue)
                    do {
                        if (try self.MOC.count(for: newFetch) > 0) {
                            //cache the result and return it
                            let obj: NSManagedObject = try self.MOC.fetch(newFetch)[0] as! NSManagedObject
                            self.objectCache[key] = obj
                            return obj
                        }
                    }
                    catch {
                        let nserror: NSError = error as NSError
                        print(nserror)
                    }
                }
            }
            self.objectCache[key] = self.blankObject //remember the nil result
            return nil
        }
    }
    
    //fetch a code matching a given key - or nil if no response
    fileprivate func fetchCode(_ entityName: String, code: String) -> NSManagedObject? {
        let objectKey: Duplet<String, String> = Duplet<String, String>(entityName, code)
        return self.fetchKeyFromCache(objectKey)
    }
    
    //find a pair in the cache (or create one if not there)
    fileprivate func fetchPair(from: Station, to: Station) -> Pair {
        let pairKey: Duplet<Station, Station> = Duplet<Station, Station>(from, to)
        
        //can we find it in the cache?
        if let pair: Pair = self.pairCache[pairKey] {
            return pair //found existing
        }
        
        //try to find it in the data base
        let pairFetch: NSFetchRequest = NSFetchRequest<Pair>(entityName: "Pair")
        pairFetch.fetchLimit = 1
        let fromPredicate: NSPredicate = NSPredicate(format: "from == %@", from)
        let toPredicate: NSPredicate = NSPredicate(format: "to == %@", to)
        let datasetPredicate: NSPredicate = NSPredicate(format: "dataset == %@", self.dataSet!)
        pairFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fromPredicate, toPredicate, datasetPredicate])
        do {
            let pairs: [Pair] = try self.MOC.fetch(pairFetch)
            if pairs.count > 0 {
                //add to existing pair
                let pair: Pair = pairs[0]
                self.pairCache[pairKey] = pair
                return pair
            }
        }
        catch {
            //ignore
        }
        
        //create a new blank pair
        let pairDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Pair", in: self.MOC)
        let pair: Pair = NSManagedObject(entity: pairDescription!, insertInto: self.MOC) as! Pair
        pair.setValue(self.dataSet, forKey: "dataset")
        pair.setValue(0, forKey: "count")
        pair.setValue(from, forKey: "from")
        pair.setValue(to, forKey: "to")
        self.pairCache[pairKey] = pair
        return pair
    }
    
    //convenience method to set time values on an NSManagedObject.
    fileprivate func setTimeFromString(_ object: NSManagedObject, timeString: String, keyName: String) {
        let timePair: (hour: Int, minute: Int)? = timeString.hhmmTime()
        if (timePair != nil) {
            object.setValue(timePair!.hour, forKey: keyName + "_hour")
            object.setValue(timePair!.minute, forKey: keyName + "_minute")
        }
    }
    
    //deal with looking up station -> get tiploc, then use that to get station
    fileprivate func fetchStationFromTiploc(_ tiplocCode: String) -> Station? {
        //deal with looking up station -> get tiploc, then use that to get station
        if let tiploc: NSManagedObject = fetchCode("Tiploc", code: tiplocCode) {
            if let tiplocStation: Station = tiploc.value(forKey: "station") as? Station {
                return (tiplocStation)
            }
        }
        return nil
    }
    
    //convenience method to replicate the common part of creation a routeEntry for start (LO), middle (LI) and end lines (LT)
    fileprivate func createRouteEntryFromCodes(_ tiplocCode: String, scheduledDeparture: String, publicDeparture: String, scheduledArrival: String, publicArrival: String, scheduledPass: String, platform: String, line: String, activityCodes: [String]) -> NSManagedObject? {
        //can't do anything without a station
        if let station: Station = fetchStationFromTiploc(tiplocCode) {
            
            //create and deal with simple objects first - flat values
            let routeEntryDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "RouteEntry", in: self.MOC)
            let newRouteEntry: NSManagedObject = NSManagedObject(entity: routeEntryDescription!, insertInto: self.MOC)
            newRouteEntry.setValue(self.dataSet!, forKey: "dataset")
            newRouteEntry.setValue(station, forKey: "station")
            if (platform.characters.count > 0) {
                newRouteEntry.setValue(platform, forKey: "platform")
            }
            if (line.characters.count > 0) {
                newRouteEntry.setValue(line, forKey: "line")
            }
            
            //check we have at least one date
            if (scheduledDeparture == "") && (publicDeparture == "") && (scheduledArrival == "") && (publicArrival == "") && (scheduledPass == "") {
                return nil
            }
            
            //deal with dates - parse into time objects
            setTimeFromString(newRouteEntry, timeString: scheduledDeparture, keyName: "scheduled_departure")
            setTimeFromString(newRouteEntry, timeString: scheduledArrival, keyName: "scheduled_arrival")
            setTimeFromString(newRouteEntry, timeString: scheduledPass, keyName: "scheduled_pass")
            setTimeFromString(newRouteEntry, timeString: publicDeparture, keyName: "public_departure")
            setTimeFromString(newRouteEntry, timeString: publicDeparture, keyName: "public_departure")
            
            //deal with setting the activities
            let activities: NSMutableSet = NSMutableSet()
            for code in activityCodes {
                if (code.characters.count > 0) {
                    let activity: NSManagedObject? = fetchCode("Activity", code: code)
                    if (activity != nil) {
                        activities.add(activity!)
                    }
                }
            }
            newRouteEntry.setValue(activities, forKey: "activities")
            return newRouteEntry
        }
        return nil
    }
    
    //define codes based on data spec, and add to core data if not already present
    fileprivate func loadConstants() {
        //update status
        self.progressViewController?.updateIndeterminate("Importing constants and codes into database.")
        
        let atoc_codes: [String: String] = [
            "AW": "Arriva Trains Wales",
            "CC": "c2c",
            "CH": "Chiltern Railways",
            "CT": "Central Trains",
            "EM": "East Midlands Trains",
            "ES": "Eurostar",
            "FC": "First Capital Connect",
            "GC": "Grand Central",
            "GR": "GNER",
            "GW": "First Great Western",
            "GX": "Gatwick Express",
            "HC": "Heathrow Connect",
            "HT": "Hull Trains",
            "HX": "Heathrow Express",
            "IL": "Island Line",
            "LE": "one",
            "LM": "London Midlands",
            "LO": "London Overground",
            "ME": "Merseyrail",
            "ML": "Midland Mainline",
            "NT": "Northern",
            "NY": "North Yorkshire Moors Railway",
            "SE": "Southeastern",
            "SN": "Southern",
            "SR": "First ScotRail",
            "SS": "Silverlink Train Services",
            "SW": "South West Trains",
            "TP": "First TransPennine Express",
            "VT": "Virgin Trains",
            "WR": "West Coast Railway Co",
            "XC": "CrossCountry"
        ]
        
        let category_codes: [String: (category: String, subcategory: String)] = [
            "OL": ("Ordinary passenger trains", "London Underground"),
            "OU": ("Ordinary passenger trains", "Unadvertised ordinary passenger"),
            "OO": ("Ordinary passenger trains", "Ordinary passenger"),
            "OS": ("Ordinary passenger trains", "Staff train"),
            "OW": ("Ordinary passenger trains", "Mixed"),
            "XC": ("Express passenger trains", "Channel Tunnel"),
            "XD": ("Express passenger trains", "Sleeper (Europe night service"),
            "XI": ("Express passenger trains", "International"),
            "XR": ("Express passenger trains", "Motorail"),
            "XU": ("Express passenger trains", "Unadvertised express"),
            "XX": ("Express passenger trains", "Express passenger"),
            "XZ": ("Express passenger trains", "Sleeper (Domestic)"),
            "BR": ("Bus", "Rail replacement bus"),
            "BS": ("Bus", "Timetabled service"), //WTT service - working timetable
            "EE": ("Empty coaching stock", "Empty coaching stock"),
            "EL": ("Empty coaching stock", "Empty coaching stock, London Underground"),
            "ES": ("Empty coaching stock", "Empty coaching stock and staff"),
            "JJ": ("Parcels and postal trains", "Postal"),
            "PM": ("Parcels and postal trains", "Post Office Controlled Parcels"),
            "PP": ("Parcels and postal trains", "Parcels"),
            "PV": ("Parcels and postal trains", "Empty"),
            "DD": ("Departmental trains", "Departmental"),
            "DH": ("Departmental trains", "Civil engineer"),
            "DI": ("Departmental trains", "Mechanical and electrical engineer"),
            "DQ": ("Departmental trains", "Stores"),
            "DT": ("Departmental trains", "Test"),
            "DY": ("Departmental trains", "Signal and telecommunications engineer"),
            "ZB": ("Light locomotives", "Locomotive and brake van"),
            "ZZ": ("Light locomotives", "Light locomotive"),
            "J2": ("Railfreight distribution", "RfD automotive (components)"),
            "H2": ("Railfreight distribution", "RfD automotive (vehicles)"),
            "J3": ("Railfreight distribution", "RfD edible products (UK contracts)"),
            "J4": ("Railfreight distribution", "RfD industrial minerals (components)"),
            "J5": ("Railfreight distribution", "RfD chemicals (components)"),
            "J6": ("Railfreight distribution", "RfD building materials (components)"),
            "J8": ("Railfreight distribution", "RfD general merchandise (components)"),
            "H8": ("Railfreight distribution", "RfD European"),
            "J9": ("Railfreight distribution", "RfD freightliner (contracts)"),
            "H9": ("Railfreight distribution", "RfD freightliner (other)"),
            "A0": ("Trainload freight", "Coal (distributive)"),
            "E0": ("Trainload freight", "Coal (electricity)"),
            "B0": ("Trainload freight", "Coal (other) and nuclear"),
            "B1": ("Trainload freight", "Metals"),
            "B4": ("Trainload freight", "Aggregates"),
            "B5": ("Trainload freight", "Domestic and industrial waste"),
            "B6": ("Trainload freight", "Building materials"),
            "B7": ("Trainload freight", "Petroleum products"),
            "H0": ("Railfreight distribution (Channel Tunnel)", "RfD European Channel Tunnel (mixed business)"),
            "H1": ("Railfreight distribution (Channel Tunnel)", "RfD European Channel Tunnel intermodal"),
            "H3": ("Railfreight distribution (Channel Tunnel)", "RfD European Channel Tunnel automotive"),
            "H4": ("Railfreight distribution (Channel Tunnel)", "RfD European Channel Tunnel contract services"),
            "H5": ("Railfreight distribution (Channel Tunnel)", "RfD European Channel Tunnel haulmark"),
            "H6": ("Railfreight distribution (Channel Tunnel)", "RfD European Channel Tunnel joint venture"),
            "SS": ("Ship", "Ship")
        ]
        
        let catering_codes: [String: String] = [
            "C": "Buffet service",
            "F": "Restaurant car for first class passengers",
            "H": "Service of hot food available",
            "M": "Meal included for first class passengers",
            "P": "Wheelchair-only reservations",
            "R": "Restaurant",
            "T": "Trolley service"
        ]
        
        let power_codes: [String: String] = [
            "D": "Diesel",
            "DEM": "Diesel electric multiple unit",
            "DMU": "Diesel mechanical multiple unit",
            "E": "Electric",
            "ED": "Electro-diesel",
            "EML": "Electric multiple unit plus diesel/electric/electro-diesel locomotive",
            "EMU": "Electric multiple unit",
            "EPU": "Electric parcels unit",
            "HST": "High speed train",
            "LDS": "Diesel shunting locomotive"
        ]
        
        let reservation_codes: [String: String] = [
            "A": "Seat reservations compulsory",
            "E": "Reservations for bicycles essential",
            "R": "Seat reservations recommended",
            "S": "Seat reservations possible from any station"
        ]
        
        let sleeper_codes: [String: String] = [
            "B": "First and standard class",
            "F": "First class only",
            "S": "Standard class only"
        ]
        
        let class_codes: [String: String] = [
            " ": "First and standard class",
            "B": "First and standard class",
            "S": "Standard class only"
        ]
        
        let activity_codes: [String: String] = [
            "A": "Stops or shunts for other trains to pass",
            "AE": "Attach/detach assisting locomotive",
            "BL": "Stops for banking locomotive",
            "C": "Stops to change trainmen",
            "D": "Stops to set down passengers",
            "-D": "Stops to detach vehicles",
            "E": "Stops for examination",
            "G": "National Rail Timetable data to add",
            "H": "Notional activity to prevent WTT timing columns merge",
            "HH": "Notional activity to prevent WTT timing columns merge",
            "K": "Passenger count point",
            "KC": "Ticket collection and examination point",
            "KE": "Ticket examination point",
            "KF": "Ticket examination point, first class only",
            "KS": "Selective ticket examination point",
            "L": "Stops to change locomotives",
            "N": "Stop not advertised",
            "OP": "Stops for other operating reasons",
            "OR": "Train locomotive on rear",
            "PR": "Propelling between points shown",
            "R": "Stops when required",
            "RM": "Reversing motion, or driver changes ends",
            "RR": "Stops for locomotive to run round train",
            "S": "Stops for railway personnel only",
            "T": "Stops to take up and set down passengers",
            "-T": "Stops to attach and detach vehicles",
            "TB": "Train begins",
            "TF": "Train finishes",
            "TS": "Detail Consist for TOPS Direct requested by EWS",
            "TW": "Stops (or at pass) or tablet, staff or token",
            "U": "Stops to take up passengers",
            "-U": "Stops to attach vehicles",
            "W": "Stops for watering of coaches",
            "X": "Passes another train at crossing point on single line"
        ]
        
        let linkModes: [String] = ["BUS", "TUBE", "WALK", "FERRY", "METRO", "TRAM", "TAXI", "TRANSFER"]
        
        let weekdays: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        
        //now load data in if it doesn't exist
        self.createObjectsForConstantCodes(atoc_codes, entityName: "ATOC")
        self.createObjectsForConstantCodes(catering_codes, entityName: "Catering")
        self.createObjectsForConstantCodes(power_codes, entityName: "Power")
        self.createObjectsForConstantCodes(reservation_codes, entityName: "Reservation")
        self.createObjectsForConstantCodes(sleeper_codes, entityName: "Sleeper")
        self.createObjectsForConstantCodes(class_codes, entityName: "Class")
        self.createObjectsForConstantCodes(activity_codes, entityName: "Activity")
        
        //this one is different because it has two sets of values to add
        let categoryFetch: NSFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Category")
        do {
            if (try self.MOC.count(for: categoryFetch) == 0) {
                for (key, value) in category_codes {
                    let categoryEntityDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Category", in: self.MOC)
                    let categoryEntity: NSManagedObject = NSManagedObject(entity: categoryEntityDescription!, insertInto: self.MOC)
                    categoryEntity.setValue(key, forKey: "code")
                    categoryEntity.setValue(value.category, forKey: "category")
                    categoryEntity.setValue(value.subcategory, forKey: "subcategory")
                    let categoryKey: Duplet<String, String> = Duplet<String, String>("Category", key)
                    self.objectCache[categoryKey] = categoryEntity
                }
            }
        }
        catch {
            let nserror: NSError = error as NSError
            print(nserror)
        }
        
        //this one is different because they need to be in order
        let weekdayFetch: NSFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Weekday")
        do {
            if (try self.MOC.count(for: weekdayFetch) == 0) {
                let weekdayDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Weekday", in: self.MOC)
                for weekday in weekdays {
                    let weekdayEntity: NSManagedObject = NSManagedObject(entity: weekdayDescription!, insertInto: self.MOC)
                    weekdayEntity.setValue(weekday, forKey: "string")
                    let weekdayNumber: Int = weekdays.index(of: weekday)!
                    weekdayEntity.setValue(weekdayNumber, forKey: "number")
                    let weekdayKey: Duplet<String, String> = Duplet<String, String>("Weekday", String(weekdayNumber))
                    self.objectCache[weekdayKey] = weekdayEntity
                }
            }
        }
        catch {
            let nserror: NSError = error as NSError
            print(nserror)
        }
        
        //this one is different because there is no code
        let linkModeFetch: NSFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "LinkMode")
        do {
            if (try self.MOC.count(for: linkModeFetch) == 0) {
                let linkModeDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "LinkMode", in: self.MOC)
                for (modeName) in linkModes {
                    let newModeName: String = modeName.lowercased().capitalized
                    let linkModeEntity: NSManagedObject = NSManagedObject(entity: linkModeDescription!, insertInto: self.MOC)
                    linkModeEntity.setValue(newModeName, forKey: "string")
                    let linkModeKey: Duplet<String, String> = Duplet<String, String>("LinkMode", newModeName)
                    self.objectCache[linkModeKey] = linkModeEntity
                }
            }
        }
        catch {
            let nserror: NSError = error as NSError
            print(nserror)
        }
    }
    
    //encapsulate process as need to run it for both MCA and ZTR files
    fileprivate func processTrainArray(_ array: [String], arrayStart: Int, filename: String) {
        //now load the MCA data with info on trains and routes - we already found its path
        let trainDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Train", in: self.MOC)
        
        //the in the MCA file are not isolated, so need to store info together in one place, and reuse as needed. Must be outside the loop
        var routeEntries: NSMutableOrderedSet = NSMutableOrderedSet()
        var trainDays: [Bool] = [Bool](repeating: false, count: 7)
        var startDate: Date = Date()
        var endDate: Date = Date()
        var id: String = String()
        var uid: String = String()
        var categoryCode: String = String()
        var powerCode: String = String()
        var speed: Int = Int()
        var classCode: String = String()
        var sleeperCode: String = String()
        var reservationsCode: String = String()
        var cateringCodes: [String] = [String]()
        var englishBankHolidays: Bool = false
        var scottishBankHolidays: Bool = false
        var atocCode: String = String()
        
        var previousRouteEntry: RouteEntry? //so we can make a linked list
        
        //helps with formatting
        let progressNumberFormatter: NumberFormatter = NumberFormatter()
        progressNumberFormatter.numberStyle = .decimal
        progressNumberFormatter.hasThousandSeparators = true
        
        //loop through the data line by line
        var trainDataCount: Int = 0
        var trainCount: Int = 0
        self.importCount += arrayStart
        var lineCount: Int = 0
        for mcaLine in array[arrayStart..<array.count] {
            self.importCount += 1
            
            if (filename == "mca") {
                self.mcaProgress += 1
            }
            if (filename == "ztr") {
                self.ztrProgress += 1
            }
            
            lineCount += 1
            trainDataCount += 1
            if self.isCancelled {
                self.MOC.rollback()
                return
            }
            
            let progressString: String = "Processing " + filename.uppercased() + " train data - line " + progressNumberFormatter.string(from: NSNumber(value: arrayStart + lineCount))! + " of " + progressNumberFormatter.string(from: NSNumber(value: array.count))! + "."
            let progressValue: Double = Double(self.importCount) / Double(self.totalCount)
            self.progressViewController?.updateDeterminate(progressString, doubleValue: progressValue, updateBar: (self.importCount % self.updateLimit == 0))
            
            if (mcaLine.characters.count < 10) { //ignore short lines
                continue
            }
            
            autoreleasepool {
                let recordType: String = mcaLine.substring(0, end: 1)
                switch(recordType) {
                case "BS": //basic details -> days running
                    //this is the start of a new route so close off the old one
                    trainCount += 1
                    
                    if ((trainCount > 1) && (arrayStart < array.count)) { //check it's not the first time we've found a BS line
                        //create the object, and cache it
                        let newTrain: NSManagedObject = NSManagedObject(entity: trainDescription!, insertInto: self.MOC)
                        
                        //set constant values that don't depend on looking up other types of thing
                        newTrain.setValue(self.dataSet!, forKey: "dataset")
                        newTrain.setValue(uid, forKey: "uid")
                        newTrain.setValue(id, forKey: "id")
                        newTrain.setValue(startDate, forKey: "start")
                        newTrain.setValue(endDate, forKey: "end")
                        newTrain.setValue(speed, forKey: "speed")
                        newTrain.setValue(englishBankHolidays, forKey: "runsOnEnglishBankHolidays")
                        newTrain.setValue(scottishBankHolidays, forKey: "runsOnScottishBankHolidays")
                        
                        //go and fetch lookups for codes and add to the objects
                        newTrain.setValue(self.fetchCode("ATOC", code: atocCode), forKey: "atoc")
                        newTrain.setValue(self.fetchCode("Category", code: categoryCode), forKey: "category")
                        newTrain.setValue(self.fetchCode("Power", code: powerCode), forKey: "power")
                        newTrain.setValue(self.fetchCode("Class", code: classCode), forKey: "class_type")
                        newTrain.setValue(self.fetchCode("Sleeper", code: sleeperCode), forKey: "sleeper")
                        newTrain.setValue(self.fetchCode("Reservation", code: reservationsCode), forKey: "reservations")
                        
                        //deal with the days it runs on
                        let runsOn: NSMutableSet = NSMutableSet()
                        var daysCount: Int = 0
                        for i in 0 ..< 7 {
                            if (trainDays[i] == true) {
                                daysCount += 1
                                if let thisDay: NSManagedObject = self.fetchCode("Weekday", code: String(i)) {
                                    runsOn.add(thisDay)
                                }
                            }
                        }
                        newTrain.setValue(runsOn, forKey: "runsOn")
                        
                        //set each of the routeEntries to this train
                        previousRouteEntry = nil
                        for routeEntry in routeEntries {
                            let re: RouteEntry = routeEntry as! RouteEntry
                            re.setValue(newTrain, forKey: "train") //set the one-side of the many-to-one relationship
                            if (previousRouteEntry != nil) {
                                //maintain doubly linked list
                                re.setValue(previousRouteEntry!, forKey: "prev")
                                previousRouteEntry!.setValue(re, forKey: "next")
                                
                                //make the relevant pair (or recycle existing if you can)
                                let pair: Pair = self.fetchPair(from: previousRouteEntry!.station!, to: re.station!)
                                re.setValue(pair, forKey: "prevPair")
                                previousRouteEntry!.setValue(pair, forKey: "nextPair")
                                let newCount: Int = pair.count!.intValue + daysCount
                                pair.setValue(newCount, forKey: "count")
                            }
                            previousRouteEntry = re
                        }
                        
                        //look up all of the catering codes and add a set to the train
                        let caterings: NSMutableSet = NSMutableSet()
                        for code in cateringCodes {
                            let cateringKey: Duplet<String, String> = Duplet<String, String>("Catering", code)
                            if let cateringResult: NSManagedObject = fetchKeyFromCache(cateringKey) {
                                caterings.add(cateringResult)
                            }
                        }
                        if (caterings.count > 0) {
                            newTrain.setValue(caterings, forKey: "catering")
                        }
                        
                        if (trainCount % updateLimit == 0) {
                            if (lineCount > 0) { //don't do it just on resuming
                                //save the dataset after all the data is loaded
                                self.progressViewController?.updateDeterminate("Saving imported data.", doubleValue: 0, updateBar: false)
                                if (filename == "mca") {
                                    self.dataSet!.setValue(self.mcaProgress - 1, forKey: "mcaProgress") //less one, because we will need to go back and re-load the details from the BS line for the first train next time
                                    self.saveImport(String(self.mcaProgress) + " lines from MCA file")
                                }
                                if (filename == "ztr") {
                                    self.dataSet!.setValue(self.ztrProgress - 1, forKey: "ztrProgress")
                                    self.saveImport(String(self.ztrProgress) + " lines from ZTR file")
                                }
                            }
                        }
                    }
                    
                    //reset the collection for the next set of lines
                    routeEntries = NSMutableOrderedSet()
                    
                    //load in details of when the train runs
                    for i in 0...6 {
                        trainDays[i] = mcaLine[mcaLine.characters.index(mcaLine.startIndex, offsetBy: 21 + i)] == "1"
                    }
                    let startString: String = mcaLine.substring(9, end: 14)
                    startDate = startString.yymmddDate()!
                    let endString: String = mcaLine.substring(15, end: 20)
                    endDate = endString.yymmddDate()!
                    
                    let bankHolidaysCharacter: Character = mcaLine[mcaLine.characters.index(mcaLine.startIndex, offsetBy: 28)]
                    switch (bankHolidaysCharacter) {
                    case "X":
                        englishBankHolidays = true //Runs on English bank holidays
                        scottishBankHolidays = false
                        break
                    case "G":
                        englishBankHolidays = false //Runs on Scottish bank holidays
                        scottishBankHolidays = true
                        break
                    default:
                        englishBankHolidays = false //Does not run on bank holidays
                        scottishBankHolidays = false
                        break
                    }
                    
                    //extract other details from the line
                    uid = mcaLine.substring(3, end: 8)
                    categoryCode = mcaLine.substring(30, end: 31)
                    id = mcaLine.substring(32, end: 35)
                    powerCode = mcaLine.substring(50, end: 52)
                    if Int(mcaLine.substring(57, end: 59)) != nil {
                        speed = Int(mcaLine.substring(57, end: 59))!
                    }
                    else {
                        speed = 0
                    }
                    classCode = String(mcaLine[mcaLine.characters.index(mcaLine.startIndex, offsetBy: 66)])
                    sleeperCode = String(mcaLine[mcaLine.characters.index(mcaLine.startIndex, offsetBy: 67)])
                    reservationsCode = String(mcaLine[mcaLine.characters.index(mcaLine.startIndex, offsetBy: 68)])
                    
                    //catering can have multiple codes so get them all as separate strings
                    let cateringCharacters: String = mcaLine.substring(70, end: 73)
                    cateringCodes = []
                    for code in cateringCharacters.characters {
                        if code != " " {
                            cateringCodes.append(String(code))
                        }
                    }
                    break
                    
                case "BX": //additional details, but not interested in any of them except the ATOC code
                    atocCode = mcaLine.substring(11, end: 12)
                    break
                    
                case "LO": //origin station -- ignoring details of
                    let tiplocCode: String = mcaLine.substring(2, end: 8, trimDashes: true)
                    let scheduledDeparture: String = mcaLine.substring(10, end: 13)
                    let publicDeparture: String = mcaLine.substring(15, end: 18)
                    let platform: String = mcaLine.substring(19, end: 21)
                    let line: String = mcaLine.substring(22, end: 24)
                    
                    //activities is a group of 6 pairs of characters, so plit them out
                    let activityCodesString: String = mcaLine.substring(29, end: 40, trim: false)
                    var activityCodes: [String] = [String]()
                    for i in 0...(activityCodesString.characters.count - 1) where i % 2 == 0 {
                        let codePair: String = activityCodesString.substring(i, end: i + 1, trim: true)
                        if ((codePair != "  ") && (codePair != " ") && (codePair != "")) { //some activity codes are single letters so pair could have a space which will be trimmed
                            activityCodes.append(codePair.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                        }
                    }
                    
                    //now formulate a routeEntry with that info if we found any
                    if let newRouteEntry: NSManagedObject = self.createRouteEntryFromCodes(tiplocCode, scheduledDeparture: scheduledDeparture, publicDeparture: publicDeparture, scheduledArrival: "", publicArrival: "", scheduledPass: "", platform: platform, line: line, activityCodes: activityCodes) {
                        routeEntries.add(newRouteEntry)
                    }
                    break
                    
                case "LI": //intermediate station
                    let tiplocCode: String = mcaLine.substring(2, end: 8, trimDashes: true)
                    let scheduledArrival: String = mcaLine.substring(10, end: 13)
                    let scheduledDeparture: String = mcaLine.substring(15, end: 18)
                    let scheduledPass: String = mcaLine.substring(20, end: 23)
                    let publicArrival: String = mcaLine.substring(25, end: 28)
                    let publicDeparture: String = mcaLine.substring(29, end: 32)
                    let platform: String = mcaLine.substring(33, end: 35)
                    let line: String = mcaLine.substring(36, end: 38)
                    
                    let activityCodesString: String = mcaLine.substring(42, end: 53, trim: false)
                    var activityCodes: [String] = [String]()
                    for i in 0...(activityCodesString.characters.count - 1) where i % 2 == 0 {
                        let codePair: String = activityCodesString.substring(i, end: i + 1)
                        if ((codePair != "  ") && (codePair != " ") && (codePair != "")) { //some activity codes are single letters so pair could have a space which will be trimmed
                            activityCodes.append(codePair)
                        }
                    }
                    
                    if let newRouteEntry: NSManagedObject = self.createRouteEntryFromCodes(tiplocCode, scheduledDeparture: scheduledDeparture, publicDeparture: publicDeparture, scheduledArrival: scheduledArrival, publicArrival: publicArrival, scheduledPass: scheduledPass, platform: platform, line: line, activityCodes: activityCodes) {
                        routeEntries.add(newRouteEntry)
                    }
                    break
                    
                case "CR": //change en route -- ignore for now. bit too complicated
                    break
                    
                case "LT": //terminus station
                    let tiplocCode: String = mcaLine.substring(2, end: 8, trimDashes: true)
                    let scheduledArrival: String = mcaLine.substring(10, end: 13)
                    let publicArrival: String = mcaLine.substring(15, end: 18)
                    let platform: String = mcaLine.substring(19, end: 21)
                    
                    //activities is a group of 6 pairs of characters, so plit them out
                    let activityCodesString: String = mcaLine.substring(25, end: 36, trim: false)
                    var activityCodes: [String] = [String]()
                    for i in 0...(activityCodesString.characters.count - 1) where i % 2 == 0 {
                        let codePair: String = activityCodesString.substring(i, end: i + 1)
                        if ((codePair != "  ") && (codePair != " ") && (codePair != "")) { //some activity codes are single letters so pair could have a space which will be trimmed
                            activityCodes.append(codePair)
                        }
                    }
                    
                    if let newRouteEntry: NSManagedObject = self.createRouteEntryFromCodes(tiplocCode, scheduledDeparture: "", publicDeparture: "", scheduledArrival: scheduledArrival, publicArrival: publicArrival, scheduledPass: "", platform: platform, line: "", activityCodes: activityCodes) {
                        routeEntries.add(newRouteEntry)
                    }
                    
                    break
                    
                case "AA": //association - think this is for where a train splits in two. Not interested
                    break
                    
                default: //ignore the others
                    break
                }
            }
        }
        
        //also need to run through and make the last train after the last time through the loop
        if (uid.characters.count > 0) { //check it's not the initializer
            //create the object
            let newTrain: NSManagedObject = NSManagedObject(entity: trainDescription!, insertInto: self.MOC)
            
            //set constant values that don't depend on looking up other types of thing
            newTrain.setValue(self.dataSet!, forKey: "dataset")
            newTrain.setValue(uid, forKey: "uid")
            newTrain.setValue(id, forKey: "id")
            newTrain.setValue(routeEntries, forKey: "routeEntries")
            newTrain.setValue(startDate, forKey: "start")
            newTrain.setValue(endDate, forKey: "end")
            newTrain.setValue(speed, forKey: "speed")
            newTrain.setValue(englishBankHolidays, forKey: "runsOnEnglishBankHolidays")
            newTrain.setValue(scottishBankHolidays, forKey: "runsOnScottishBankHolidays")
            
            //go and fetch lookups for codes and add to the objects
            newTrain.setValue(self.fetchCode("ATOC", code: atocCode), forKey: "atoc")
            newTrain.setValue(self.fetchCode("Category", code: categoryCode), forKey: "category")
            newTrain.setValue(self.fetchCode("Power", code: powerCode), forKey: "power")
            newTrain.setValue(self.fetchCode("Class", code: classCode), forKey: "class_type")
            newTrain.setValue(self.fetchCode("Sleeper", code: sleeperCode), forKey: "sleeper")
            newTrain.setValue(self.fetchCode("Reservation", code: reservationsCode), forKey: "reservations")
            
            //deal with the days it runs on
            let runsOn: NSMutableSet = NSMutableSet()
            var daysCount: Int = 0
            for i in 0 ..< 7 {
                if (trainDays[i] == true) {
                    daysCount += 1
                    if let thisDay: NSManagedObject = self.fetchCode("Weekday", code: String(i)) {
                        runsOn.add(thisDay)
                    }
                }
            }
            newTrain.setValue(runsOn, forKey: "runsOn")
            
            //set each of the routeEntries to this train
            previousRouteEntry = nil
            for routeEntry in routeEntries {
                let re: RouteEntry = routeEntry as! RouteEntry
                re.setValue(newTrain, forKey: "train") //set the one-side of the many-to-one relationship
                if (previousRouteEntry != nil) {
                    //maintain doubly linked list
                    re.setValue(previousRouteEntry!, forKey: "prev")
                    previousRouteEntry!.setValue(re, forKey: "next")
                    
                    //make the relevant pair (or recycle existing if you can)
                    let pair: Pair = self.fetchPair(from: previousRouteEntry!.station!, to: re.station!)
                    re.setValue(pair, forKey: "prevPair")
                    previousRouteEntry!.setValue(pair, forKey: "nextPair")
                    let newCount: Int = pair.count!.intValue + daysCount
                    pair.setValue(newCount, forKey: "count")
                }
                previousRouteEntry = re
            }
            
            //look up all of the catering codes and add a set to the train
            let caterings: NSMutableSet = NSMutableSet()
            for code in cateringCodes {
                let cateringCode: Duplet<String, String> = Duplet<String, String>("Catering", code)
                if let cateringResult: NSManagedObject = self.fetchKeyFromCache(cateringCode) {
                    caterings.add(cateringResult)
                }
            }
            if (caterings.count > 0) {
                newTrain.setValue(caterings, forKey: "catering")
            }
            
            //save the dataset after all the data is loaded
            if (lineCount > 0) { //don't do it just on resuming
                //save the dataset after all the data is loaded
                self.progressViewController?.updateDeterminate("Saving imported data.", doubleValue: 0, updateBar: false)
                if (filename == "mca") {
                    self.dataSet!.setValue(self.mcaProgress, forKey: "mcaProgress")
                    self.saveImport("all train data from MCA file")
                }
                if (filename == "ztr") {
                    self.dataSet!.setValue(self.ztrProgress, forKey: "ztrProgress")
                    self.saveImport(String(self.ztrProgress) + "all train data from ZTR file")
                }
            }
        }
    }

    //rebuild cache if resuming
    fileprivate func rebuildObjectCache() {
        let totalProgress: Int = self.msnProgress + self.mcaProgress + self.ztrProgress + self.alfProgress
        if (totalProgress == 0) {
            return
        }
        //go through the things we want in the cache
        for (entityType, keys) in self.entityKeys {
            let entityFetch: NSFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityType)
            do {
                let entityResults: [NSFetchRequestResult] = try self.MOC.fetch(entityFetch)
                for entityResult in entityResults {
                    for key in keys { //add it in by each key available
                        let entityKey: Duplet<String, String> = Duplet<String, String>(entityType, key)
                        self.objectCache[entityKey] = (entityResult as! NSManagedObject)
                    }
                }
            }
            catch {}
        }
    }
    
    override func main() {
        //check for cancellation at the start - will do so again during the life
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        
        self.progressViewController?.updateIndeterminate("Checking for necessary files in directory.")
        
        //find the data directory and the file we chose
        let datasetName: String = self.chosenFile.deletingPathExtension().lastPathComponent
        let directoryPath: URL = self.chosenFile.deletingLastPathComponent()
        
        //check directory contains all the files we expect - .alf, .mca, .msn, .ztr
        let dataFileTypes: [String] = ["msn", "mca", "alf", "ztr"]
        for dataFileType in dataFileTypes {
            let expectedFilePath: URL = directoryPath.appendingPathComponent(datasetName + "." + dataFileType)
            
            //non-critical error - just stop loading
            if (!self.fileExists(expectedFilePath)) {
                DispatchQueue.main.async(execute: {
                    let alert: NSAlert = NSAlert();
                    alert.alertStyle = NSAlertStyle.warning
                    alert.messageText = "Unable to load data from directory";
                    alert.informativeText = "Could not find expected file - " + expectedFilePath.absoluteString
                    alert.runModal();
                })
                return //stop without doing anything
            }
        }
        
        //first, let's check if the data already exists, if so don't load it
        let samedataSetFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Dataset")
        samedataSetFetch.predicate = NSPredicate(format: "name == %@", datasetName)
        do {
            if (try self.MOC.count(for: samedataSetFetch) > 0) {
                
                //find out where we got to last time
                do {
                    self.dataSet = try self.MOC.fetch(samedataSetFetch)[0] as? NSManagedObject
                    self.msnProgress = self.dataSet!.value(forKey: "msnProgress") as! Int
                    self.mcaProgress = self.dataSet!.value(forKey: "mcaProgress") as! Int
                    self.ztrProgress = self.dataSet!.value(forKey: "ztrProgress") as! Int
                    self.alfProgress = self.dataSet!.value(forKey: "alfProgress") as! Int
                }
                catch {
                }
                
                //rebuild the object cache to save time
                self.rebuildObjectCache()
            }
        }
        catch {
            let nserror: NSError = error as NSError
            print(nserror)
        }
        
        if (self.dataSet == nil) { //create a new dataset if we don't already have one
            
            //Start by defining the dataset
            let newDataSetEntity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Dataset", in: self.MOC)
            let newDataSet: NSManagedObject = NSManagedObject(entity: newDataSetEntity!, insertInto: self.MOC)
            newDataSet.setValue(datasetName, forKey: "name")
            newDataSet.setValue(Date(), forKey: "date_loaded")
            self.dataSet = newDataSet
        }
        
        //load in the constants -- if we don't have them
        self.loadConstants() //functions already check whether we have all the constants/definitions we need first
        
        //get the date modified from the MCA file loaded
        let mcaFilePath: URL = directoryPath.appendingPathComponent(datasetName + ".mca")
        do {
            let mcaAttributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: mcaFilePath.absoluteString)
            self.dataSet!.setValue(mcaAttributes[FileAttributeKey.modificationDate], forKey: "date_modified")
        }
        catch { //if in doubt, set as extreme date and carry on
            self.dataSet!.setValue(Date.distantPast, forKey: "date_modified")
        }
        
        //load in all the data - need it up front to have a sense of progress for progress bar
        let msnFilePath: URL = directoryPath.appendingPathComponent(datasetName + ".msn")
        let ztrFilePath: URL = directoryPath.appendingPathComponent(datasetName + ".ztr")
        let alfFilePath: URL = directoryPath.appendingPathComponent(datasetName + ".alf")
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        self.progressViewController?.updateIndeterminate("Loading " + msnFilePath.lastPathComponent.uppercased())
        var msnData: [String] = self.readFileLines(msnFilePath)
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        self.progressViewController?.updateIndeterminate("Loading " + mcaFilePath.lastPathComponent.uppercased())
        var mcaData: [String] = self.readFileLines(mcaFilePath)
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        self.progressViewController?.updateIndeterminate("Loading " + ztrFilePath.lastPathComponent.uppercased())
        var ztrData: [String] = self.readFileLines(ztrFilePath)
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        self.progressViewController?.updateIndeterminate("Loading " + alfFilePath.lastPathComponent.uppercased())
        var alfData: [String] = self.readFileLines(alfFilePath)
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        
        //check there is something there in each file
        let dataFiles: [[String]] = [msnData, mcaData, ztrData, alfData]
        for dataFile in dataFiles {
            if dataFile.count == 0 {
                return
            }
        }
        
        //variables to keep track of progress
        let progressNumberFormatter: NumberFormatter = NumberFormatter()
        progressNumberFormatter.numberStyle = .decimal
        progressNumberFormatter.hasThousandSeparators = true
        self.importCount = self.msnProgress //skip ahead if we can
        self.totalCount = msnData.count + mcaData.count + ztrData.count + alfData.count
        
        let saveMSN: Bool = self.msnProgress < msnData.count //will only need to save if we started before the end
        
        //now load the underlying data. Start with stations - in the .MSN file
        for msnLine in msnData[msnData.indices.suffix(from: self.msnProgress)] {
            autoreleasepool {
            self.msnProgress += 1
            self.importCount += 1
            if self.isCancelled {
                self.MOC.rollback()
                return
            }
                
            let progressString: String = "Loading station data - line " + progressNumberFormatter.string(from: NSNumber(value: self.msnProgress))! + " of " + progressNumberFormatter.string(from: NSNumber(value: msnData.count))! + "."
            let progressValue: Double = Double(self.importCount) / Double(self.totalCount)
            self.progressViewController?.updateDeterminate(progressString, doubleValue: progressValue, updateBar: (self.importCount % self.updateLimit == 0))
            
            if (msnLine.characters.count > 0) {
                //how to process each line depends on
                let firstChar: Character = msnLine[msnLine.startIndex]
                switch(firstChar) {
                case "A": //actual station
                    if (msnLine[msnLine.characters.index(msnLine.startIndex, offsetBy: 5)] != " ") { //this is the timestamp line
                        //make new station - predefined data format, things at certain positions on each row
                        var stationName: String = msnLine.substring(3, end: 34)
                        stationName = stationName.formatName()//capitalize and then fix errors in name processing
                        
                        //other properties
                        let cate: Int = Int(String((msnLine.characters[msnLine.characters.index(msnLine.startIndex, offsetBy: 35)])))! //0: Not an interchange, 1: Small interchange, 2: medium interchange, 3: large interchange, 9: subsidiary TIPLOC at station with more than one
                        let tiploc: String = msnLine.substring(36, end: 42) //timing point location code
                        let subsidiaryCRS: String = msnLine.substring(43, end: 45) //3-alpha code
                        let mainCRS: String = msnLine.substring(49, end: 51) //3-alpha code
                        let easting: Int = Int(msnLine.substring(52, end: 56))! //geographic coordinates. Units of 100m. 10000 = Carrick on Shannon, 18690 = Amsterdam
                        let northing: Int = Int(msnLine.substring(58, end: 62))! //geographic coordinates. Units of 100m. 60126 = Lizard (Bus), 69703 = Scrabster
                        let changeTime: Int = Int(msnLine.substring(63, end: 65))!
                        
                        //load them into an object
                        let newStationEntity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Station", in: self.MOC)
                        let newStation: NSManagedObject = NSManagedObject(entity: newStationEntity!, insertInto: self.MOC)
                        newStation.setValue(self.dataSet!, forKey: "dataset")
                        newStation.setValue(stationName, forKey: "name")
                        self.objectCache[Duplet<String, String>("Station", stationName)] = newStation //cache by name
                        newStation.setValue(cate, forKey: "cate")
                        if (subsidiaryCRS != mainCRS) {
                            newStation.setValue(subsidiaryCRS, forKey: "crs_subsidiary")
                            self.objectCache[Duplet<String, String>("Station", subsidiaryCRS)] = newStation //cache by CRS
                        }
                        newStation.setValue(mainCRS, forKey: "crs_main")
                        self.objectCache[Duplet<String, String>("Station", mainCRS)] = newStation //cache by CRS
                        newStation.setValue(easting, forKey: "easting")
                        newStation.setValue(northing, forKey: "northing")
                        newStation.setValue(changeTime, forKey: "change_time")
                        
                        
                        //create a tiploc entry
                        let tiplocEntityDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Tiploc", in: self.MOC)
                        let tiplocEntity: NSManagedObject = NSManagedObject(entity: tiplocEntityDescription!, insertInto: self.MOC)
                        tiplocEntity.setValue(self.dataSet!, forKey: "dataset")
                        tiplocEntity.setValue(tiploc, forKey: "code")
                        tiplocEntity.setValue(newStation, forKey: "station")
                        let tiplocKey: Duplet<String, String> = Duplet<String, String>("Tiploc", tiploc)
                        self.objectCache[tiplocKey] = tiplocEntity
                    }
                    break
                    
                case "C": //station comments. Historic and should be ignored
                    break
                    
                case "L": //alias. Process and save as an alias object
                    do {
                        //find the original station using its name
                        var mainName: String = msnLine.substring(3, end: 35)
                        mainName = mainName.formatName()
                        let stationNameKey: Duplet<String, String> = Duplet<String, String>("Station", mainName)
                        if let thisStation: NSManagedObject = fetchKeyFromCache(stationNameKey) {
                        
                            //get the alias name
                            var aliasName: String = msnLine.substring(36, end: 66)
                            aliasName = aliasName.formatName()
                            
                            //create an object and link the alias to the station
                            let newAliasEntity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Alias", in: self.MOC)
                            let newAlias: NSManagedObject = NSManagedObject(entity: newAliasEntity!, insertInto: self.MOC)
                            newAlias.setValue(aliasName, forKey: "name")
                            newAlias.setValue(self.dataSet!, forKey: "dataset")
                            newAlias.setValue(thisStation, forKey: "station")
                        }
                    }
                    break
                    
                case "G": //group. Historic and should be ignored
                    break
                    
                case "R": //routing group for non-National Rail. Historic and should be ignored
                    break
                    
                case "V": //Routing groups used today -> process and save as a group object
                    //extract the group name
                    var groupName: String = msnLine.substring(3, end: 35)
                    groupName = groupName.formatName()
                    
                    //extract the station three-letter codes
                    let groupCodesString: String = msnLine.substring(36, end: 76)
                    let groupCodes: [String] = groupCodesString.components(separatedBy: " ")
                    
                    //compile a list of actual stations
                    let groupStations: NSMutableSet = NSMutableSet()
                    for code in groupCodes {
                        let crsKey: Duplet<String, String> = Duplet<String, String>("Station", code)
                        if let thisStation: NSManagedObject = fetchKeyFromCache(crsKey) {
                            groupStations.add(thisStation)
                        }
                    }
                    
                    //if we found something then make a group object
                    if (groupStations.count > 0) {
                        let newGroupEntity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Group", in: self.MOC)
                        let newGroup: NSManagedObject = NSManagedObject(entity: newGroupEntity!, insertInto: self.MOC)
                        newGroup.setValue(groupName, forKey: "name")
                        newGroup.setValue(self.dataSet!, forKey: "dataset")
                        newGroup.setValue(groupStations, forKey: "stations")
                    }
                    break
                    
                default:
                    break
                }
            }
            }
        }
        msnData = [] //free up memory
        
        //save the dataset after all the data is loaded
        if (saveMSN) {
            self.progressViewController?.updateDeterminate("Saving imported data.", doubleValue: 0, updateBar: false)
            self.dataSet!.setValue(self.msnProgress, forKey: "msnProgress")
            self.saveImport("stations")
        }
        
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        processTrainArray(mcaData, arrayStart: self.mcaProgress, filename: "mca")
        
        if self.isCancelled {
            self.MOC.rollback()
            return
        }
        
        processTrainArray(ztrData, arrayStart: self.ztrProgress, filename: "ztr")

        //reset arrays to save space
        mcaData = []
        ztrData = []
        
        //now import the ALF fixed links data
        let dateFormatter: DateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let linkDescription: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Link", in: self.MOC)
        self.importCount += self.alfProgress //skip ahead if we can
        
        let saveALF: Bool = self.alfProgress < alfData.count //will only need to save if we started before the end
        
        for alfLine in alfData[alfData.indices.suffix(from: self.alfProgress)] {
            autoreleasepool {
            self.alfProgress += 1
            self.importCount += 1
            if self.isCancelled {
                self.MOC.rollback()
                return
            }
            let progressString: String = "Loading fixed link data - line " + progressNumberFormatter.string(from: NSNumber(value: self.alfProgress))! + " of " + progressNumberFormatter.string(from: NSNumber(value: alfData.count))! + "."
            let progressValue: Double = Double(self.importCount) / Double(self.totalCount)
            self.progressViewController?.updateDeterminate(progressString, doubleValue: progressValue, updateBar: (self.importCount % self.updateLimit == 0))
            
            if (alfLine.characters.count > 0) {
                if (alfLine[alfLine.startIndex] == "M") {
                    
                    //values we will fill in
                    var origin: NSManagedObject?
                    var destination: NSManagedObject?
                    var start_hour: Int?
                    var start_minute: Int?
                    var end_hour: Int?
                    var end_minute: Int?
                    var time: Int?
                    var priority: Int?
                    var start_date: Date?
                    var end_date: Date?
                    var days: NSMutableSet?
                    var mode: AnyObject?
                    
                    //now extract the rest
                    let alfParts: [String] = alfLine.components(separatedBy: ",") //comma separated values
                    for alfPart in alfParts {
                        let alfPartParts: [String] = alfPart.components(separatedBy: "=") //key before the =, value after
                        switch(alfPartParts[0]) { //treat differently depending on value
                            case "M": //mode
                                let modeName: String = alfPartParts[1].lowercased().capitalized
                                mode = self.fetchCode("LinkMode", code: modeName)
                                break
                            
                            case "O": //origin station
                                let stationCode: String = alfPartParts[1]
                                origin = self.fetchCode("Station", code: stationCode)
                                break
                            
                            case "D": //destination station
                                let stationCode: String = alfPartParts[1]
                                destination = self.fetchCode("Station", code: stationCode)
                                break
                            
                            case "T": //time taken
                                time = Int(alfPartParts[1])
                                break
                            
                            case "S": //start time in hhmm format
                                let timeParts: (hour: Int, minute: Int)? = alfPartParts[1].hhmmTime()
                                if (timeParts != nil) {
                                    start_hour = timeParts!.hour
                                    start_minute = timeParts!.minute
                                }
                                break
                            
                            case "E": //end time in hhmm format
                                let timeParts: (hour: Int, minute: Int)? = alfPartParts[1].hhmmTime()
                                if (timeParts != nil) {
                                    end_hour = timeParts!.hour
                                    end_minute = timeParts!.minute
                                }
                                break
                            
                            case "P": //priority
                                priority = Int(alfPartParts[1])
                                break
                            
                            case "F": //optional start date in dd/mm/yyyy format
                                start_date = dateFormatter.date(from: alfPartParts[1])
                                break
                            
                            case "U": //optional end date in dd/mm/yyyy format
                                end_date = dateFormatter.date(from: alfPartParts[1])
                                break
                            
                            case "R": //0 or 1 for each day of the week, starting with Monday
                                days = NSMutableSet()
                                var dayCount: Int = 0
                                for dayCharacter in alfPartParts[1].characters {
                                    if (dayCharacter == "1") { //only need the ones where it runs on
                                        if let thisDay: NSManagedObject = self.fetchCode("Weekday", code: String(dayCount)) {
                                            days!.add(thisDay)
                                        }
                                    }
                                    dayCount += 1
                                }
                                break
                        
                            default:
                                break
                        }
                    }
                    
                    //cope with optional dates
                    if (start_date == nil) {
                        start_date = Date.distantPast
                    }
                    if (end_date == nil) {
                        end_date = Date.distantFuture
                    }
                    
                    //check we have something for each field and skip if not
                    let non_optional_fields: [Any?] = [origin, destination, start_hour, start_minute, end_hour, end_minute, time, priority, start_date, end_date, days, mode] as [Any?]
                    var all_fields_complete: Bool = true
                    for field in non_optional_fields {
                        if field == nil {
                            all_fields_complete = false
                            break
                        }
                    }
                    
                    if (all_fields_complete) {
                        //if have everything, then make the object
                        let linkEntity: NSManagedObject = NSManagedObject(entity: linkDescription!, insertInto: self.MOC)
                        linkEntity.setValue(origin, forKey: "origin")
                        linkEntity.setValue(destination, forKey: "destination")
                        linkEntity.setValue(mode, forKey: "mode")
                        linkEntity.setValue(self.dataSet!, forKey: "dataset")
                        linkEntity.setValue(start_hour, forKey: "start_hour")
                        linkEntity.setValue(start_minute, forKey: "start_minute")
                        linkEntity.setValue(end_hour, forKey: "end_hour")
                        linkEntity.setValue(end_minute, forKey: "end_minute")
                        linkEntity.setValue(time, forKey: "time")
                        linkEntity.setValue(priority, forKey: "priority")
                        linkEntity.setValue(days, forKey: "runsOn")
                    }
                }
            }
            }
        }
        alfData = [] //free up memory
    
        //save the dataset after all the data is loaded
        if (saveALF) {
            self.progressViewController?.updateDeterminate("Saving imported data.", doubleValue: 0, updateBar: false)
            self.dataSet!.setValue(self.alfProgress, forKey: "alfProgress")
            self.saveImport("fixed link data")
        }
    }
}
