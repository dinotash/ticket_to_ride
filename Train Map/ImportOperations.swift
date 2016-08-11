//
//  ImportOperations.swift
//  Train Map
//
//  Created by Tom Curtis on 5 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

//https://www.raywenderlich.com/76341/use-nsoperation-nsoperationqueue-swift

//queue of imports to be done
class PendingOperations {
    lazy var importsInProgress = [NSOperation]()
    lazy var importQueue: NSOperationQueue = {
        var queue = NSOperationQueue()
        queue.name = "Import queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
}

//where we actually do the import
class ttisImporter: NSOperation {
    
    //keep track of variables set outside the operation -> passed in on init()
    let MOC: NSManagedObjectContext //Need a separate managed object context for the separate thread
    let chosenFile: NSURL //file we selected
    let progressViewController: ProgressViewController?
    let updateLimit = 10000 //how many iterations before updating progress bar
    
    //cache results for some of the codes we will want to fetch later
    var objectCache: [Duplet<String, String> : NSManagedObject] = [:] //(entityType, ID) : Object
    
    //initialize the variables used within the thread
    init(chosenFile: NSURL, progressViewController: ProgressViewController?) {
        
        //create MOC from scratch
        let coordinator = (NSApplication.sharedApplication().delegate as! AppDelegate).persistentStoreCoordinator
        self.MOC = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        self.MOC.persistentStoreCoordinator = coordinator
        self.MOC.undoManager = nil //makes it go faster, apparently
        
        //pass along other variables for later use
        self.progressViewController = progressViewController
        self.chosenFile = chosenFile
        super.init()
        
        self.qualityOfService = .Utility //don't need to hold things up immediately for this
    }
    
    //when loading files, check each expected file exists
    private func fileExists(expectedFilePath: NSURL) -> Bool {
        return (NSFileManager.defaultManager().fileExistsAtPath(expectedFilePath.relativePath!))
    }
    
    //convenience method used in loadConstants() to actually create the objects
    private func createObjectsForConstantCodes(codes: [String: String], entityName: String) {
        let entityFetch = NSFetchRequest(entityName: entityName)
        if (self.MOC.countForFetchRequest(entityFetch, error: nil) == 0) { //add only if not already there
            let newEntityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: self.MOC)
            for (key, value) in codes {
                let newEntity = NSManagedObject(entity: newEntityDescription!, insertIntoManagedObjectContext: self.MOC)
                newEntity.setValue(key, forKey: "code")
                newEntity.setValue(value, forKey: "string")
                let cacheKey = Duplet<String, String>(entityName, key)
                self.objectCache[cacheKey] = newEntity
            }
        }
    }
    
    //function to take a file and read it in line by line, giving an array at the end
    private func readFileLines(path: NSURL) -> [String]? {
        do {
            //load the data, split into lines
            let fileData = try String(contentsOfFile: path.relativePath!, encoding: NSUTF8StringEncoding)
            let fileLines = fileData.componentsSeparatedByString("\n")
            return fileLines
        }
        catch {
            dispatch_async(dispatch_get_main_queue(), {
                let alert = NSAlert();
                alert.alertStyle = NSAlertStyle.WarningAlertStyle
                alert.messageText = "Unable to load data from file";
                alert.informativeText = "Could not load data from file " + path.relativePath!
                alert.runModal();
            })
            return nil //stop without doing anything
        }
    }
    
    //fetch a code matching a given key - or nil if no response
    private func fetchCode(entityName: String, code: String) -> NSManagedObject? {
        let objectKey = Duplet<String, String>(entityName, code)
        if self.objectCache[objectKey] != nil {
            return self.objectCache[objectKey]
        }
        //couldn't find cached, so try to fetch
        else {
            return nil
        }
    }
    
    //convenience method to set time values on an NSManagedObject.
    private func setTimeFromString(object: NSManagedObject, timeString: String, keyName: String) {
        let timePair = timeString.hhmmTime()
        if (timePair != nil) {
            object.setValue(timePair!.hour, forKey: keyName + "_hour")
            object.setValue(timePair!.minute, forKey: keyName + "_minute")
        }
    }
    
    //deal with looking up station -> get tiploc, then use that to get station
    private func fetchStationFromTiploc(tiplocCode: String) -> NSManagedObject? {
        //deal with looking up station -> get tiploc, then use that to get station
        if let tiploc = fetchCode("Tiploc", code: tiplocCode) {
            if let tiplocStation = tiploc.valueForKey("station") {
                return (tiplocStation as! NSManagedObject)
            }
        }
        return nil
    }
    
    //convenience method to replicate the common part of creation a routeEntry for start (LO), middle (LI) and end lines (LT)
    private func createRouteEntryFromCodes(tiplocCode: String, scheduledDeparture: String, publicDeparture: String, scheduledArrival: String, publicArrival: String, scheduledPass: String, platform: String, line: String, activityCodes: [String], dataset: NSManagedObject) -> NSManagedObject? {
        //can't do anything without a station
        if let station = fetchStationFromTiploc(tiplocCode) {
            
            //create and deal with simple objects first - flat values
            let routeEntryDescription = NSEntityDescription.entityForName("RouteEntry", inManagedObjectContext: self.MOC)
            let newRouteEntry = NSManagedObject(entity: routeEntryDescription!, insertIntoManagedObjectContext: self.MOC)
            newRouteEntry.setValue(dataset, forKey: "dataset")
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
            let activities = NSMutableSet()
            for code in activityCodes {
                if (code.characters.count > 0) {
                    let activity = fetchCode("Activity", code: code)
                    if (activity != nil) {
                        activities.addObject(activity!)
                    }
                }
            }
            newRouteEntry.setValue(activities, forKey: "activities")
            return newRouteEntry
        }
        return nil
    }
    
    //define codes based on data spec, and add to core data if not already present
    private func loadConstants() {
        //update status
        self.progressViewController?.progressLabel.stringValue = "Importing constants and codes into database."
        self.progressViewController?.updateIndeterminate("Woo eggs")
        
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
        
        let linkModes = ["BUS", "TUBE", "WALK", "FERRY", "METRO", "TRAM", "TAXI", "TRANSFER"]
        
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        
        //now load data in if it doesn't exist
        self.createObjectsForConstantCodes(atoc_codes, entityName: "ATOC")
        self.createObjectsForConstantCodes(catering_codes, entityName: "Catering")
        self.createObjectsForConstantCodes(power_codes, entityName: "Power")
        self.createObjectsForConstantCodes(reservation_codes, entityName: "Reservation")
        self.createObjectsForConstantCodes(sleeper_codes, entityName: "Sleeper")
        self.createObjectsForConstantCodes(class_codes, entityName: "Class")
        self.createObjectsForConstantCodes(activity_codes, entityName: "Activity")
        
        //this one is different because it has two sets of values to add
        let categoryFetch = NSFetchRequest(entityName: "Category")
        if (self.MOC.countForFetchRequest(categoryFetch, error: nil) == 0) {
            for (key, value) in category_codes {
                let categoryEntityDescription = NSEntityDescription.entityForName("Category", inManagedObjectContext: self.MOC)
                let categoryEntity = NSManagedObject(entity: categoryEntityDescription!, insertIntoManagedObjectContext: self.MOC)
                categoryEntity.setValue(key, forKey: "code")
                categoryEntity.setValue(value.category, forKey: "category")
                categoryEntity.setValue(value.subcategory, forKey: "subcategory")
            }
        }
        
        //this one is different because they need to be in order
        let weekdayFetch = NSFetchRequest(entityName: "Weekday")
        if (self.MOC.countForFetchRequest(weekdayFetch, error: nil) == 0) {
            let weekdayDescription = NSEntityDescription.entityForName("Weekday", inManagedObjectContext: self.MOC)
            for weekday in weekdays {
                let weekdayEntity = NSManagedObject(entity: weekdayDescription!, insertIntoManagedObjectContext: self.MOC)
                weekdayEntity.setValue(weekday, forKey: "string")
                let weekdayNumber = weekdays.indexOf(weekday)!
                weekdayEntity.setValue(weekdayNumber, forKey: "number")
            }
        }
        
        //this one is different because there is no code
        let linkModeFetch = NSFetchRequest(entityName: "LinkMode")
        if (self.MOC.countForFetchRequest(linkModeFetch, error: nil) == 0) {
            let linkModeDescription = NSEntityDescription.entityForName("LinkMode", inManagedObjectContext: self.MOC)
            for (modeName) in linkModes {
                let newModeName = modeName.lowercaseString.capitalizedString
                let linkModeEntity = NSManagedObject(entity: linkModeDescription!, insertIntoManagedObjectContext: self.MOC)
                linkModeEntity.setValue(newModeName, forKey: "string")
            }
        }
    }
    
    override func main() {
        //check for cancellation at the start - will do so again during the life
        if self.cancelled {
            return
        }
        
        self.progressViewController?.updateIndeterminate("Checking for necessary files in directory.")
        
        //find the data directory and the file we chose
        let datasetName = self.chosenFile.URLByDeletingPathExtension!.lastPathComponent!
        let directoryPath = self.chosenFile.URLByDeletingLastPathComponent!
        
        //check directory contains all the files we expect - .alf, .mca, .msn, .ztr
        let dataFileTypes = ["msn", "mca", "alf", "ztr"]
        for dataFileType in dataFileTypes {
            let expectedFilePath = directoryPath.URLByAppendingPathComponent(datasetName + "." + dataFileType)
            
            //non-critical error - just stop loading
            if (!self.fileExists(expectedFilePath)) {
                dispatch_async(dispatch_get_main_queue(), {
                    let alert = NSAlert();
                    alert.alertStyle = NSAlertStyle.WarningAlertStyle
                    alert.messageText = "Unable to load data from directory";
                    alert.informativeText = "Could not find expected file - " + expectedFilePath.absoluteString
                    alert.runModal();
                })
                return //stop without doing anything
            }
        }
        
        //if we get this far, it means we found all the files we need so load them in
        var newData = true //assume we have new data
        
        //first, let's check if the data already exists, if so don't load it
        let samedataSetFetch = NSFetchRequest(entityName: "Dataset")
        samedataSetFetch.predicate = NSPredicate(format: "name == %@", datasetName)
        if (self.MOC.countForFetchRequest(samedataSetFetch, error: nil) > 0) {
            newData = false
            dispatch_async(dispatch_get_main_queue(), {
                let alert = NSAlert();
                alert.alertStyle = NSAlertStyle.InformationalAlertStyle
                alert.messageText = "Unable to load data from directory";
                alert.informativeText = "Dataset " + datasetName + " has already been loaded"
                alert.runModal();
            })
            return //stop without doing anything
        }
        
        if (newData) { //only load data if we don't already have the dataset
            
            //load in the constants -- if we don't have them
            self.loadConstants() //functions already check whether we have all the constants/definitions we need first
            
            //Start by defining the dataset
            let newDataSetEntity = NSEntityDescription.entityForName("Dataset", inManagedObjectContext: self.MOC)
            let newDataSet = NSManagedObject(entity: newDataSetEntity!, insertIntoManagedObjectContext: self.MOC)
            newDataSet.setValue(datasetName, forKey: "name")
            newDataSet.setValue(NSDate(), forKey: "date_loaded")
            
            //get the date modified from the MCA file loaded
            let mcaFilePath = directoryPath.URLByAppendingPathComponent(datasetName + ".mca")
            do {
                let mcaAttributes = try NSFileManager.defaultManager().attributesOfItemAtPath(mcaFilePath.absoluteString)
                newDataSet.setValue(mcaAttributes[NSFileModificationDate], forKey: "date_modified")
            }
            catch { //if in doubt, set as extreme date and carry on
                newDataSet.setValue(NSDate.distantPast(), forKey: "date_modified")
            }
            
            //load in all the data - need it up front to have a sense of progress for progress bar
            let msnFilePath = directoryPath.URLByAppendingPathComponent(datasetName + ".msn")
            let ztrFilePath = directoryPath.URLByAppendingPathComponent(datasetName + ".ztr")
            let alfFilePath = directoryPath.URLByAppendingPathComponent(datasetName + ".alf")
            if self.cancelled {
                return
            }
            self.progressViewController?.updateIndeterminate("Loading " + msnFilePath.lastPathComponent!.uppercaseString)
            var msnData = self.readFileLines(msnFilePath)
            if self.cancelled {
                return
            }
            self.progressViewController?.updateIndeterminate("Loading " + mcaFilePath.lastPathComponent!.uppercaseString)
            var mcaData = self.readFileLines(mcaFilePath)
            if self.cancelled {
                return
            }
            self.progressViewController?.updateIndeterminate("Loading " + ztrFilePath.lastPathComponent!.uppercaseString)
            var ztrData = self.readFileLines(ztrFilePath)
            if self.cancelled {
                return
            }
            self.progressViewController?.updateIndeterminate("Loading " + alfFilePath.lastPathComponent!.uppercaseString)
            var alfData = self.readFileLines(alfFilePath)
            if self.cancelled {
                return
            }
            
            //check there is something there in each file
            let dataFiles = [msnData, mcaData, ztrData, alfData]
            for dataFile in dataFiles {
                if (dataFile == nil) {
                    return
                }
                if dataFile!.count == 0 {
                    return
                }
            }
            
            //variables to keep track of progress
            let progressNumberFormatter = NSNumberFormatter()
            progressNumberFormatter.numberStyle = .DecimalStyle
            progressNumberFormatter.hasThousandSeparators = true
            var importCount = 0
            let totalCount = msnData!.count + mcaData!.count + ztrData!.count + alfData!.count
            
            //now load the underlying data. Start with stations - in the .MSN file
            var msnCount = 0
            for msnLine in msnData! {
                autoreleasepool {
                msnCount += 1
                importCount += 1
                if self.cancelled {
                    return
                }
                let progressString = "Loading station data - line " + progressNumberFormatter.stringFromNumber(msnCount)! + " of " + progressNumberFormatter.stringFromNumber(msnData!.count)! + "."
                let progressValue = Double(importCount) / Double(totalCount)
                self.progressViewController?.updateDeterminate(progressString, doubleValue: progressValue, updateBar: (importCount % updateLimit == 0))
                
                if (msnLine.characters.count > 0) {
                    //how to process each line depends on
                    let firstChar = msnLine[msnLine.startIndex]
                    switch(firstChar) {
                    case "A":
                        if (msnLine[msnLine.startIndex.advancedBy(5)] != " ") { //this is the timestamp line
                            //make new station - predefined data format, things at certain positions on each row
                            var stationName = msnLine.substring(3, end: 34)
                            stationName = stationName.formatName()//capitalize and then fix errors in name processing
                            
                            //other properties
                            let cate = Int(String((msnLine.characters[msnLine.startIndex.advancedBy(35)]))) //0: Not an interchange, 1: Small interchange, 2: medium interchange, 3: large interchange, 9: subsidiary TIPLOC at station with more than one
                            let tiploc = msnLine.substring(36, end: 42) //timing point location code
                            let subsidiaryCRS = msnLine.substring(43, end: 45) //3-alpha code
                            let mainCRS = msnLine.substring(49, end: 51) //3-alpha code
                            let easting = Int(msnLine.substring(52, end: 56))! //geographic coordinates. Units of 100m. 10000 = Carrick on Shannon, 18690 = Amsterdam
                            let northing = Int(msnLine.substring(58, end: 62))! //geographic coordinates. Units of 100m. 60126 = Lizard (Bus), 69703 = Scrabster
                            let changeTime = Int(msnLine.substring(63, end: 65))!
                            
                            //load them into an object
                            let newStationEntity = NSEntityDescription.entityForName("Station", inManagedObjectContext: self.MOC)
                            let newStation = NSManagedObject(entity: newStationEntity!, insertIntoManagedObjectContext: self.MOC)
                            newStation.setValue(newDataSet, forKey: "dataset")
                            newStation.setValue(stationName, forKey: "name")
                            newStation.setValue(cate, forKey: "cate")
                            if (subsidiaryCRS != mainCRS) {
                                newStation.setValue(subsidiaryCRS, forKey: "crs_subsidiary")
                            }
                            newStation.setValue(mainCRS, forKey: "crs_main")
                            newStation.setValue(easting, forKey: "easting")
                            newStation.setValue(northing, forKey: "northing")
                            newStation.setValue(changeTime, forKey: "change_time")
                            
                            //create a tiploc entry
                            let tiplocEntityDescription = NSEntityDescription.entityForName("Tiploc", inManagedObjectContext: self.MOC)
                            let tiplocEntity = NSManagedObject(entity: tiplocEntityDescription!, insertIntoManagedObjectContext: self.MOC)
                            tiplocEntity.setValue(newDataSet, forKey: "dataset")
                            tiplocEntity.setValue(tiploc, forKey: "code")
                            tiplocEntity.setValue(newStation, forKey: "station")
                            let tiplocKey = Duplet<String, String>("Tiploc", tiploc)
                            self.objectCache[tiplocKey] = tiplocEntity
                        }
                        break
                        
                    case "C": //station comments. Historic and should be ignored
                        break
                        
                    case "L": //alias. Process and save as an alias object
                        do {
                            //find the original station using its name
                            var mainName = msnLine.substring(3, end: 35)
                            mainName = mainName.formatName()
                            let stationNameKey = Duplet<String, String>("Station", mainName)
                            if let thisStation = self.objectCache[stationNameKey] {
                            
                                //get the alias name
                                var aliasName = msnLine.substring(36, end: 66)
                                aliasName = aliasName.formatName()
                                
                                //create an object and link the alias to the station
                                let newAliasEntity = NSEntityDescription.entityForName("Alias", inManagedObjectContext: self.MOC)
                                let newAlias = NSManagedObject(entity: newAliasEntity!, insertIntoManagedObjectContext: self.MOC)
                                newAlias.setValue(aliasName, forKey: "name")
                                newAlias.setValue(newDataSet, forKey: "dataset")
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
                        var groupName = msnLine.substring(3, end: 35)
                        groupName = groupName.formatName()
                        
                        //extract the station three-letter codes
                        let groupCodesString = msnLine.substring(36, end: 76)
                        let groupCodes = groupCodesString.componentsSeparatedByString(" ")
                        
                        //compile a list of actual stations
                        let groupStations = NSMutableSet()
                        for code in groupCodes {
                            let crsKey = Duplet<String, String>("Station", code)
                            if let thisStation = self.objectCache[crsKey] {
                                groupStations.addObject(thisStation)
                            }
                        }
                        
                        //if we found something then make a group object
                        if (groupStations.count > 0) {
                            let newGroupEntity = NSEntityDescription.entityForName("Group", inManagedObjectContext: self.MOC)
                            let newGroup = NSManagedObject(entity: newGroupEntity!, insertIntoManagedObjectContext: self.MOC)
                            newGroup.setValue(groupName, forKey: "name")
                            newGroup.setValue(newDataSet, forKey: "dataset")
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
            do {
                self.progressViewController?.updateIndeterminate("Saving imported data.")
                try self.MOC.save()
                print("Saved managed objects")
            } catch let error as NSError  {
                NSLog("Could not save \(error), \(error.userInfo)")
            }
            
            //now load the MCA data with info on trains and routes - we already found its path
            let trainDescription = NSEntityDescription.entityForName("Train", inManagedObjectContext: self.MOC)
            
            //the in the MCA file are not isolated, so need to store info together in one place, and reuse as needed. Must be outside the loop
            var routeEntries = NSMutableOrderedSet()
            var trainDays = [Bool](count: 7, repeatedValue: false)
            var startDate = NSDate()
            var endDate = NSDate()
            var id = String()
            var uid = String()
            var categoryCode = String()
            var powerCode = String()
            var speed = Int()
            var classCode = String()
            var sleeperCode = String()
            var reservationsCode = String()
            var cateringCodes = [String]()
            var englishBankHolidays = false
            var scottishBankHolidays = false
            var atocCode = String()
            
            //loop through the data line by line
            var trainDataCount = 0
            var trainCount = 0
            for mcaLine in (mcaData! + ztrData!) {
                importCount += 1
                trainDataCount += 1
                if self.cancelled {
                    return
                }
                
                let progressString = "Processing train data - line " + progressNumberFormatter.stringFromNumber(trainDataCount)! + " of " + progressNumberFormatter.stringFromNumber(mcaData!.count + ztrData!.count)! + "."
                let progressValue = Double(importCount) / Double(totalCount)
                self.progressViewController?.updateDeterminate(progressString, doubleValue: progressValue, updateBar: (importCount % updateLimit == 0))
                
                if (mcaLine.characters.count < 10) { //ignore short lines
                    continue
                }
                
                autoreleasepool {
                let recordType = mcaLine.substring(0, end: 1)
                switch(recordType) {
                case "BS": //basic details -> days running
                    //this is the start of a new route so close off the old one
                    trainCount += 1
                    
                    if (trainCount > 1) { //check it's not the first time we've found a BS line
                        //create the object, and cache it
                        let newTrain = NSManagedObject(entity: trainDescription!, insertIntoManagedObjectContext: self.MOC)
                        
                        //set constant values that don't depend on looking up other types of thing
                        newTrain.setValue(newDataSet, forKey: "dataset")
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
                        
                        //set each of the routeEntries to this train
                        for routeEntry in routeEntries {
                            routeEntry.setValue(newTrain, forKey: "train") //set the one-side of the many-to-one relationship
                        }
                        
                        //look up all of the catering codes and add a set to the train
                        let caterings = NSMutableSet()
                        for code in cateringCodes {
                            let cateringKey = Duplet<String, String>("Catering", code)
                            if let cateringResult = self.objectCache[cateringKey] {
                                caterings.addObject(cateringResult)
                            }
                        }
                        if (caterings.count > 0) {
                            newTrain.setValue(caterings, forKey: "catering")
                        }
                        
                        //deal with the days it runs on
                        let runsOn = NSMutableSet()
                        for i in 0 ..< 7 {
                            if (trainDays[i] == true) {
                                if let thisDay = self.fetchCode("Weekday", code: String(i)) {
                                    runsOn.addObject(thisDay)
                                }
                            }
                        }
                        newTrain.setValue(runsOn, forKey: "runsOn")
                        
                        if (trainCount % updateLimit == 0) {
                            //save the dataset after all the data is loaded
                            do {
                                self.progressViewController?.updateIndeterminate("Saving imported data.")
                                try self.MOC.save()
                                print("Saved managed objects")
                            } catch let error as NSError  {
                                print("Could not save \(error), \(error.userInfo)")
                            }
                        }
                    }
                    
                    //reset the collection for the next set of lines
                    routeEntries = NSMutableOrderedSet()
                    
                    //load in details of when the train runs
                    for i in 0...6 {
                        trainDays[i] = mcaLine[mcaLine.startIndex.advancedBy(21 + i)] == "1"
                    }
                    let startString = mcaLine.substring(9, end: 14)
                    startDate = startString.yymmddDate()!
                    let endString = mcaLine.substring(15, end: 20)
                    endDate = endString.yymmddDate()!
                    
                    let bankHolidaysCharacter = mcaLine[mcaLine.startIndex.advancedBy(28)]
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
                    classCode = String(mcaLine[mcaLine.startIndex.advancedBy(66)])
                    sleeperCode = String(mcaLine[mcaLine.startIndex.advancedBy(67)])
                    reservationsCode = String(mcaLine[mcaLine.startIndex.advancedBy(68)])
                    
                    //catering can have multiple codes so get them all as separate strings
                    let cateringCharacters = mcaLine.substring(70, end: 73)
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
                    let tiplocCode = mcaLine.substring(2, end: 8, trimDashes: true)
                    let scheduledDeparture = mcaLine.substring(10, end: 13)
                    let publicDeparture = mcaLine.substring(15, end: 18)
                    let platform = mcaLine.substring(19, end: 21)
                    let line = mcaLine.substring(22, end: 24)
                    
                    //activities is a group of 6 pairs of characters, so plit them out
                    let activityCodesString = mcaLine.substring(29, end: 40, trim: false)
                    var activityCodes = [String]()
                    for i in 0...(activityCodesString.characters.count - 1) where i % 2 == 0 {
                        let codePair = activityCodesString.substring(i, end: i + 1, trim: true)
                        if ((codePair != "  ") && (codePair != " ") && (codePair != "")) { //some activity codes are single letters so pair could have a space which will be trimmed
                            activityCodes.append(codePair.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()))
                        }
                    }
                    
//                    print("tiploc: " + tiplocCode)
//                    let key = Duplet<String, String>("Tiploc", tiplocCode)
//                    let tt = self.objectCache[key]
//                    print(tt)
//                    let tstation = tt!.valueForKey("station")
//                    print(tstation)
                    
                    //now formulate a routeEntry with that info if we found any
                    if let newRouteEntry = self.createRouteEntryFromCodes(tiplocCode, scheduledDeparture: scheduledDeparture, publicDeparture: publicDeparture, scheduledArrival: "", publicArrival: "", scheduledPass: "", platform: platform, line: line, activityCodes: activityCodes, dataset: newDataSet) {
                        routeEntries.addObject(newRouteEntry)
                    }
                    break
                    
                case "LI": //intermediate station
                    let tiplocCode = mcaLine.substring(2, end: 8, trimDashes: true)
                    let scheduledArrival = mcaLine.substring(10, end: 13)
                    let scheduledDeparture = mcaLine.substring(15, end: 18)
                    let scheduledPass = mcaLine.substring(20, end: 23)
                    let publicArrival = mcaLine.substring(25, end: 28)
                    let publicDeparture = mcaLine.substring(29, end: 32)
                    let platform = mcaLine.substring(33, end: 35)
                    let line = mcaLine.substring(36, end: 38)
                    
                    let activityCodesString = mcaLine.substring(42, end: 53, trim: false)
                    var activityCodes = [String]()
                    for i in 0...(activityCodesString.characters.count - 1) where i % 2 == 0 {
                        let codePair = activityCodesString.substring(i, end: i + 1)
                        if ((codePair != "  ") && (codePair != " ") && (codePair != "")) { //some activity codes are single letters so pair could have a space which will be trimmed
                            activityCodes.append(codePair)
                        }
                    }
                    
                    if let newRouteEntry = self.createRouteEntryFromCodes(tiplocCode, scheduledDeparture: scheduledDeparture, publicDeparture: publicDeparture, scheduledArrival: scheduledArrival, publicArrival: publicArrival, scheduledPass: scheduledPass, platform: platform, line: line, activityCodes: activityCodes, dataset: newDataSet) {
                        routeEntries.addObject(newRouteEntry)
                    }
                    break
                    
                case "CR": //change en route -- ignore for now. bit too complicated
                    break
                    
                case "LT": //terminus station
                    let tiplocCode = mcaLine.substring(2, end: 8, trimDashes: true)
                    let scheduledArrival = mcaLine.substring(10, end: 13)
                    let publicArrival = mcaLine.substring(15, end: 18)
                    let platform = mcaLine.substring(19, end: 21)
                    
                    //activities is a group of 6 pairs of characters, so plit them out
                    let activityCodesString = mcaLine.substring(25, end: 36, trim: false)
                    var activityCodes = [String]()
                    for i in 0...(activityCodesString.characters.count - 1) where i % 2 == 0 {
                        let codePair = activityCodesString.substring(i, end: i + 1)
                        if ((codePair != "  ") && (codePair != " ") && (codePair != "")) { //some activity codes are single letters so pair could have a space which will be trimmed
                            activityCodes.append(codePair)
                        }
                    }
                    
                    if let newRouteEntry = self.createRouteEntryFromCodes(tiplocCode, scheduledDeparture: "", publicDeparture: "", scheduledArrival: scheduledArrival, publicArrival: publicArrival, scheduledPass: "", platform: platform, line: "", activityCodes: activityCodes, dataset: newDataSet) {
                        routeEntries.addObject(newRouteEntry)
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
                let newTrain = NSManagedObject(entity: trainDescription!, insertIntoManagedObjectContext: self.MOC)
                
                //set constant values that don't depend on looking up other types of thing
                newTrain.setValue(newDataSet, forKey: "dataset")
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
                
                //look up all of the catering codes and add a set to the train
                let caterings = NSMutableSet()
                for code in cateringCodes {
                    let cateringCode = Duplet<String, String>("Catering", code)
                    if let cateringResult = self.objectCache[cateringCode] {
                        caterings.addObject(cateringResult)
                    }
                }
                if (caterings.count > 0) {
                    newTrain.setValue(caterings, forKey: "catering")
                }
                
                //deal with the days it runs on
                let runsOn = NSMutableSet()
                for i in 0 ..< 7 {
                    if (trainDays[i] == true) {
                        if let thisDay = self.fetchCode("Weekday", code: String(i)) {
                            runsOn.addObject(thisDay)
                        }
                    }
                }
                newTrain.setValue(runsOn, forKey: "runsOn")
            }
            //reset arrays to save space
            mcaData = []
            ztrData = []
            
            //now import the ALF fixed links data
            let dateFormatter = NSDateFormatter()
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let linkDescription = NSEntityDescription.entityForName("Link", inManagedObjectContext: self.MOC)
            var alfCount = 0
            
            for alfLine in alfData! {
                autoreleasepool {
                alfCount += 1
                importCount += 1
                if self.cancelled {
                    return
                }
                let progressString = "Loading fixed link data - line " + progressNumberFormatter.stringFromNumber(alfCount)! + " of " + progressNumberFormatter.stringFromNumber(alfData!.count)! + "."
                let progressValue = Double(importCount) / Double(totalCount)
                self.progressViewController?.updateDeterminate(progressString, doubleValue: progressValue, updateBar: (importCount % updateLimit == 0))
                
                if (alfLine.characters.count > 0) {
                    if (alfLine[alfLine.startIndex] == "M") {
                        
                        //values we will fill in
                        var origin: AnyObject?
                        var destination: AnyObject?
                        var start_hour: Int?
                        var start_minute: Int?
                        var end_hour: Int?
                        var end_minute: Int?
                        var time: Int?
                        var priority: Int?
                        var start_date: NSDate?
                        var end_date: NSDate?
                        var days: NSMutableSet?
                        var mode: AnyObject?
                        
                        //now extract the rest
                        let alfParts = alfLine.componentsSeparatedByString(",") //comma separated values
                        for alfPart in alfParts {
                            let alfPartParts = alfPart.componentsSeparatedByString("=") //key before the =, value after
                            switch(alfPartParts[0]) { //treat differently depending on value
                                case "M": //mode
                                    let modeName = alfPartParts[1].lowercaseString.capitalizedString
                                    mode = self.fetchCode("LinkMode", code: modeName)
                                    break
                                
                                case "O": //origin station
                                    let stationCode = alfPartParts[1]
                                    origin = self.fetchCode("Station", code: stationCode)
                                    break
                                
                                case "D": //destination station
                                    let stationCode = alfPartParts[1]
                                    destination = self.fetchCode("Station", code: stationCode)
                                    break
                                
                                case "T": //time taken
                                    time = Int(alfPartParts[1])
                                    break
                                
                                case "S": //start time in hhmm format
                                    let timeParts = alfPartParts[1].hhmmTime()
                                    if (timeParts != nil) {
                                        start_hour = timeParts!.hour
                                        start_minute = timeParts!.minute
                                    }
                                    break
                                
                                case "E": //end time in hhmm format
                                    let timeParts = alfPartParts[1].hhmmTime()
                                    if (timeParts != nil) {
                                        end_hour = timeParts!.hour
                                        end_minute = timeParts!.minute
                                    }
                                    break
                                
                                case "P": //priority
                                    priority = Int(alfPartParts[1])
                                    break
                                
                                case "F": //optional start date in dd/mm/yyyy format
                                    start_date = dateFormatter.dateFromString(alfPartParts[1])
                                    break
                                
                                case "U": //optional end date in dd/mm/yyyy format
                                    end_date = dateFormatter.dateFromString(alfPartParts[1])
                                    break
                                
                                case "R": //0 or 1 for each day of the week, starting with Monday
                                    days = NSMutableSet()
                                    var dayCount = 0
                                    for dayCharacter in alfPartParts[1].characters {
                                        if (dayCharacter == "1") { //only need the ones where it runs on
                                            if let thisDay = self.fetchCode("Weekday", code: String(dayCount)) {
                                                days!.addObject(thisDay)
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
                            start_date = NSDate.distantPast()
                        }
                        if (end_date == nil) {
                            end_date = NSDate.distantFuture()
                        }
                        
                        //check we have something for each field and skip if not
                        let non_optional_fields = [origin, destination, start_hour, start_minute, end_hour, end_minute, time, priority, start_date, end_date, days, mode]
                        var all_fields_complete = true
                        for field in non_optional_fields {
                            if field == nil {
                                all_fields_complete = false
                                break
                            }
                        }
                        
                        if (all_fields_complete) {
                            //if have everything, then make the object
                            let linkEntity = NSManagedObject(entity: linkDescription!, insertIntoManagedObjectContext: self.MOC)
                            linkEntity.setValue(origin, forKey: "origin")
                            linkEntity.setValue(destination, forKey: "destination")
                            linkEntity.setValue(mode, forKey: "mode")
                            linkEntity.setValue(newDataSet, forKey: "dataset")
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
            do {
                self.progressViewController?.updateIndeterminate("Saving imported data.")
                self.objectCache = [:] //reset array to free up memory
                try self.MOC.save()
                print("Saved managed objects")
            } catch let error as NSError  {
                NSLog("Could not save \(error), \(error.userInfo)")
            }
        }
    }
}