//
//  TimetableViewController.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 19 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

class TimetableWindowController: NSWindowController {
    @IBOutlet weak var stationDropDownMenu: NSMenu!
    @IBOutlet weak var timetableDatePicker: NSToolbarItem!
    
    var currentDate = Date()
    var currentStationName = ""
    var MOC: NSManagedObjectContext? = nil
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        //extract earliest and latest dates for date picker
        let timetableViewController = self.contentViewController! as! TimetableViewController
        self.MOC = timetableViewController.MOC
        
        //set the toolbar items to their defaults -- today's date, first station
        self.populateDropDown()
        self.currentStationName = self.stationDropDownMenu.item(at: 0)!.title
        let datePicker = self.timetableDatePicker.view! as! NSDatePicker
        datePicker.dateValue = Date()
        self.setDateRange()
        
        //update the contents
        self.updateTimetable()
    }
    
    fileprivate func populateDropDown() {
        //get a list of stations and re-populate the list
        let stationListFetch = NSFetchRequest<Station>(entityName: "Station")
        do {
            //TO DO:
            //  1) Add aliases
            //  3) Explore why duplicate names exist -- e.g. Highbury & Islington, London Waterloo
            
            //sort the names in order and add to the list
            self.stationDropDownMenu.removeAllItems()
            
            let stationList = try self.MOC!.fetch(stationListFetch)
            let sortedList = stationList.sorted {$0.name < $1.name}
            for station in sortedList {
                self.stationDropDownMenu.addItem(withTitle: station.name!, action: nil, keyEquivalent: "")
            }
        }
        catch {
            //do nothing
        }
    }
    
    @IBAction func chooseNewStation(_ sender: NSPopUpButtonCell) {
        self.currentStationName = sender.title
        self.setDateRange()
        self.updateTimetable()
    }
    
    func setDateRange() {
        let datePicker = self.timetableDatePicker.view! as! NSDatePicker
        let stationFetch = NSFetchRequest<Station>(entityName: "Station")
        stationFetch.fetchLimit = 1
        stationFetch.predicate = NSPredicate(format: "name == %@", self.currentStationName)
        do {
            let newStation = try self.MOC!.fetch(stationFetch)[0]
            let stationDateRange = newStation.dateRange()
            datePicker.minDate = stationDateRange.0
            datePicker.maxDate = stationDateRange.1
        }
        catch {
            datePicker.minDate = Date.distantPast
            datePicker.maxDate = Date.distantFuture
        }
        self.currentDate = datePicker.dateValue
    }
    
    @IBAction func chooseDate(_ sender: NSToolbarItem) {
        let datePicker = self.timetableDatePicker.view! as! NSDatePicker
        self.currentDate = datePicker.dateValue
        self.updateTimetable()
    }

    fileprivate func updateTimetable() {
        let timetableViewController = self.contentViewController! as! TimetableViewController
        timetableViewController.loadTimetable(self.currentStationName, date: self.currentDate)
    }
}

class TimetableViewController: NSViewController {

    @IBOutlet weak var tableView: NSTableView!

    var station: Station?
    var routeEntries: [RouteEntry]?
    let MOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType) //create MOC from scratch
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.MOC.persistentStoreCoordinator = (NSApplication.shared().delegate as! AppDelegate).persistentStoreCoordinator
        self.MOC.undoManager = nil //makes it go faster, apparently
    }
    
    fileprivate func loadTimetable(_ station: String, date: Date) {
        //get key details about the date
        let bankHoliday = date.bankHoliday()
        let weekday = date.weekday()
        
        let routeEntryFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "RouteEntry")
        var predicateList = Array<NSPredicate>()
        
        //always need right station and day of week
        predicateList.append(NSPredicate(format: "station.name == %@", station))
        predicateList.append(NSPredicate(format: "%i in train.runsOn.number", weekday - 1)) //calendar has Sunday-Sat = 1-7, whereas imported as Sun-Sat = 0-6
        predicateList.append(NSPredicate(format: "train.start < %@", date as NSDate))
        predicateList.append(NSPredicate(format: "train.end > %@", date as NSDate))
        
        //CHECK WEEKDAY NUMBERING
        
        //if it's a bank holiday then also need to know if it runs
        if bankHoliday.0 {
            predicateList.append(NSPredicate(format: "train.runsOnEnglishBankHolidays == TRUE"))
        }
        if bankHoliday.1 {
            predicateList.append(NSPredicate(format: "train.runsOnScottishBankHolidays == TRUE"))
        }
        
        routeEntryFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicateList)
        
        
        let stationFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Station")
        stationFetch.predicate = NSPredicate(format: "name == %@", station)
        do {
            self.station = try self.MOC.fetch(stationFetch)[0] as? Station
            self.routeEntries = try self.MOC.fetch(routeEntryFetch) as? [RouteEntry]
            self.routeEntries?.sort()
        } catch {
            //do nothing
        }
        
        //connect it to the data
        tableView.delegate = self
        tableView.dataSource = self
        tableView.reloadData()
    }
}


extension TimetableViewController : NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return routeEntries?.count ?? 0
    }
}

extension TimetableViewController : NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    
        var text:String = ""
        var cellIdentifier: String = ""
        
        // try and make the next row from the list of route entries
        guard let item = routeEntries?[row] as RouteEntry? else {
            return nil
        }
        
        // grab the relevant data        
        if tableColumn == tableView.tableColumns[0] {
            text = item.train!.origin()
            cellIdentifier = "timetableOrigin"
        } else if tableColumn == tableView.tableColumns[1] {
            text = item.train!.destination()
            cellIdentifier = "timetableDestination"
        } else if tableColumn == tableView.tableColumns[2] {
            text = String.timeHHMM(item.scheduled_arrival_hour!, minute: item.scheduled_arrival_minute!)
            cellIdentifier = "timetableArrival"
        } else if tableColumn == tableView.tableColumns[3] {
            text = String.timeHHMM(item.scheduled_departure_hour!, minute: item.scheduled_departure_minute!)
            cellIdentifier = "timetableDeparture"
        } else if tableColumn == tableView.tableColumns[4] {
            text = String.timeHHMM(item.scheduled_pass_hour!, minute: item.scheduled_pass_minute!)
            cellIdentifier = "timetablePass"
        } else if tableColumn == tableView.tableColumns[5] {
            if item.platform != nil {
                text = item.platform!
            }
            cellIdentifier = "timetablePlatform"
        }
        
        let cell = tableView.make(withIdentifier: cellIdentifier, owner: self) as! NSTableCellView
        cell.textField?.stringValue = text
        return cell
    }
}
