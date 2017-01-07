//
//  TrainMapViewController.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 17 Nov 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa
import MapKit

class TrainMapWindowController: NSWindowController {
    @IBOutlet weak var trainCountSlider: NSSlider!
    @IBOutlet weak var trainDatePicker: NSDatePicker!
    @IBOutlet weak var trainSpeedSlider: NSSlider!
    
    var trainMapController: TrainMapViewController? = nil
    var MOC: NSManagedObjectContext? = nil
    var count: Int = 0
    var frameInterval: Double = 0.1 //how many miliseconds between updating map?
    
    var trainMapTimer: Timer = Timer()
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        //get relevant train count for slider
        self.trainMapController = self.contentViewController! as! TrainMapViewController
        self.MOC = trainMapController!.MOC
        do {
            let trainFetch: NSFetchRequest<Train> = NSFetchRequest<Train>(entityName: "Train")
            let trainMax: Int = try self.MOC!.count(for: trainFetch)
            self.trainCountSlider.maxValue = Double(trainMax)
        }
        catch {
            print("Unable to count trains in TrainMapWindowController")
        }
        
        //set date range and begin
        self.setDateRange()
        self.trainMapTimer = Timer.scheduledTimer(timeInterval: self.frameInterval, target: self, selector: Selector("updateDate"), userInfo: nil, repeats: true)
    }
    
    @IBAction func changeTrainCount(_ sender: Any) {
        self.trainMapController!.updateTrainViewLimit(limit: Int(self.trainCountSlider.intValue))
    }
    
    func setDateRange() {
        let dateRange: (earliest: Date, latest: Date) = self.trainMapController!.trainDateRange()
        self.trainDatePicker.minDate = dateRange.earliest
        self.trainDatePicker.maxDate = dateRange.latest
    }
    
    @objc func updateDate() {
        let timeChange = self.trainSpeedSlider.doubleValue
        self.trainDatePicker.dateValue = self.trainDatePicker.dateValue.addingTimeInterval(timeChange)
    }
}

class TrainMapViewController: NSViewController, MKMapViewDelegate {
    @IBOutlet weak var mapView: TrainMapView!
    
    //for scaling pair lines
    let minPairSize: Double = 1
    let maxPairSize: Double = 60
    var minPairCount: Int = 0
    var maxPairCount: Int = 0
    
    //for scaling station sizes
    let minStationSize: Double = 2
    let maxStationSize: Double = 50
    var minStationCount: Int = 0
    var maxStationCount: Int = 0
    
    //for drawing on trains
    var trainLimit: Int = 0 //limit on how many trains to draw
    var trainDateTime: Date = Date() //current date/time shown
    var trainDateSpeed: Double = 1 //rate at which time moves forward
    var trainSet: [Train] = [] //trains with which to draw
    
    let MOC: NSManagedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType) //create MOC from scratch

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //get the MOC
        self.MOC.persistentStoreCoordinator = (NSApplication.shared().delegate as! AppDelegate).persistentStoreCoordinator
        self.MOC.undoManager = nil //makes it go faster, apparently
        
        //set up map and its location
        mapView.delegate = self
        mapView.mapType = MKMapType.satellite //allow 3d approach
        let initialLocation: CLLocation = CLLocation(latitude: 54.233560, longitude: -4.523264) //centre on the Isle of Man
        mapView.centreMapOnLocation(location: initialLocation, regionRadius: 500000)
        
        //get all the stations
        let stationFetch: NSFetchRequest = NSFetchRequest<Station>(entityName: "Station")
        let stationNorthingCheck: NSPredicate = NSPredicate(format: "northing > 0")
        let stationEastingCheck: NSPredicate = NSPredicate(format: "easting > 0")
        let stationCountCheck: NSPredicate = NSPredicate(format: "count > 0")
        stationFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [stationNorthingCheck, stationEastingCheck, stationCountCheck])
        stationFetch.sortDescriptors = [NSSortDescriptor(key: "count", ascending: true)]
        
        do {
            let stationList: [Station] = try self.MOC.fetch(stationFetch)
            if (stationList.count > 0) {
                //get the scales
                self.minStationCount = stationList[0].count!.intValue
                self.maxStationCount = stationList.last!.count!.intValue
                
                //draw the stations
                mapView.addAnnotations(stationList)
            }
        }
        catch {
            //pass
        }
        
        //work out the max and min counts through each pair by looking at order
        let pairFetch: NSFetchRequest = NSFetchRequest<Pair>(entityName: "Pair")
        let pairNorthingCheckFrom: NSPredicate = NSPredicate(format: "from.northing > 0")
        let pairEastingCheckFrom: NSPredicate = NSPredicate(format: "from.easting > 0")
        let pairNorthingCheckTo: NSPredicate = NSPredicate(format: "to.northing > 0")
        let pairEastingCheckTo: NSPredicate = NSPredicate(format: "to.easting > 0")
        pairFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [pairNorthingCheckFrom, pairEastingCheckFrom, pairNorthingCheckTo, pairEastingCheckTo])
        pairFetch.sortDescriptors = [NSSortDescriptor(key: "count", ascending: true)]
        
        do {
            let pairList: [Pair] = try self.MOC.fetch(pairFetch)
            if (pairList.count > 0) {
                self.minPairCount = pairList[0].count!.intValue
                self.maxPairCount = pairList.last!.count!.intValue
                
                //draw all the station pairs
                var pairLines: [MKPolyline] = []
                for pair in pairList {
                    if let pairLine: MKPolyline = pair.polyline {
                        pairLines.append(pairLine)
                    }
                }
                mapView.addOverlays(pairLines)
            }
        }
        catch {
            //pass
        }
    }
    
    //determine how each station should be shown
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let annotation: Station = annotation as? Station {
            let identifier: String = "stationmarker"
            var view: MKAnnotationView
            if let dequeuedView: MKPinAnnotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKPinAnnotationView {
                dequeuedView.annotation = annotation
                view = dequeuedView
            }
            else {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.canShowCallout = true
                view.image = NSImage(named: "blackCircle")
            }
            return view
        }
        return nil
    }
    
    //determine how each line should be shown
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let overlay: MKPolyline = overlay as? MKPolyline {
            //work out how to scale the line
            let overlayCount: Int = Int(overlay.subtitle!)!
            let relativeCount: Double = Double(overlayCount - self.minPairCount) / Double(self.maxPairCount - self.minPairCount)
            let relativeWidth: Double = self.minPairSize + (relativeCount * (self.maxPairSize - self.minPairSize))
            
            //render the line
            let polylineRenderer: MKPolylineRenderer = MKPolylineRenderer(polyline: overlay)
            polylineRenderer.strokeColor = NSColor.red
            polylineRenderer.alpha = 0.4
            polylineRenderer.lineWidth = CGFloat(relativeWidth)
            return polylineRenderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    //determine admissible date range
    func trainDateRange() -> (earliest: Date, latest: Date) {
        //get first result when sorted in right order
        let trainFetch: NSFetchRequest<Train> = NSFetchRequest(entityName: "Train")
        trainFetch.fetchLimit = 1
        let earliestSort = NSSortDescriptor(key: "start", ascending: true)
        let latestSort = NSSortDescriptor(key: "end", ascending: false)
        
        //earliest date first
        var earliestDate: Date = Date.distantPast
        do {
            trainFetch.sortDescriptors = [earliestSort]
            let earliestResults: [Train] = try self.MOC.fetch(trainFetch)
            earliestDate = earliestResults[0].value(forKey: "start") as! Date
        }
        catch {
            //pass
        }
        
        //then latest
        var latestDate: Date = Date.distantFuture
        do {
            trainFetch.sortDescriptors = [latestSort]
            let latestResults: [Train] = try self.MOC.fetch(trainFetch)
            latestDate = latestResults[0].value(forKey: "end") as! Date
        }
        catch {
            //pass
        }
        
        return (earliest: earliestDate, latest: latestDate)
    }
    
    //receive updated train limit from slider in toolbar
    func updateTrainViewLimit(limit: Int) {
        self.trainLimit = limit
    }
    
    
}

class TrainMapView: MKMapView {
    
    func centreMapOnLocation(location: CLLocation, regionRadius: CLLocationDistance) {
        let coordinateRegion: MKCoordinateRegion = MKCoordinateRegionMakeWithDistance(location.coordinate, regionRadius * 2.0, regionRadius * 2.0)
        self.setRegion(coordinateRegion, animated: true)
    }
}
