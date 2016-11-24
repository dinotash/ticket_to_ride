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

class TrainMapViewController: NSViewController, MKMapViewDelegate {
    @IBOutlet weak var mapView: TrainMapView!
    
    let minSize: Double = 1
    let maxSize: Double = 40
    var minCount: Int = 0
    var maxCount: Int = 0
    
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
        do {
            let stationList: [Station] = try self.MOC.fetch(stationFetch)
            for station in stationList {
                if (Int(station.northing!) > 0) && (Int(station.easting!) > 0) {
                    mapView.addAnnotation(station)
                }
            }
        }
        catch {
            //pass
        }
        
        //work out the max and min counts through each pair by looking at order
        let pairFetch: NSFetchRequest = NSFetchRequest<Pair>(entityName: "Pair")
        let northingCheckFrom: NSPredicate = NSPredicate(format: "from.northing > 0")
        let eastingCheckFrom: NSPredicate = NSPredicate(format: "from.easting > 0")
        let northingCheckTo: NSPredicate = NSPredicate(format: "to.northing > 0")
        let eastingCheckTo: NSPredicate = NSPredicate(format: "to.easting > 0")
        pairFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [northingCheckFrom, eastingCheckFrom, northingCheckTo, eastingCheckTo])
        pairFetch.sortDescriptors = [NSSortDescriptor(key: "count", ascending: true)]
        
        do {
            let pairList: [Pair] = try self.MOC.fetch(pairFetch)
            if (pairList.count > 0) {
                self.minCount = pairList[0].count!.intValue
                self.maxCount = pairList.last!.count!.intValue
                
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
    
    //determine how each annotation should be shown
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
            let relativeCount: Double = Double(overlayCount - self.minCount) / Double(self.maxCount - self.minCount)
            let relativeWidth: Double = self.minSize + (relativeCount * (self.maxSize - self.minSize))
            
            //render the line
            let polylineRenderer: MKPolylineRenderer = MKPolylineRenderer(polyline: overlay)
            polylineRenderer.strokeColor = NSColor.red
            polylineRenderer.alpha = 0.4
            polylineRenderer.lineWidth = CGFloat(relativeWidth)
            return polylineRenderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

class TrainMapView: MKMapView {
    
    func centreMapOnLocation(location: CLLocation, regionRadius: CLLocationDistance) {
        let coordinateRegion: MKCoordinateRegion = MKCoordinateRegionMakeWithDistance(location.coordinate, regionRadius * 2.0, regionRadius * 2.0)
        self.setRegion(coordinateRegion, animated: true)
    }
}
