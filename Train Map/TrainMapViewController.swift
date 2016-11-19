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
//    @IBOutlet weak var mapView: TrainMapView!
    @IBOutlet weak var mapView: TrainMapView!
    
    
    let MOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType) //create MOC from scratch
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //get the MOC
        self.MOC.persistentStoreCoordinator = (NSApplication.shared().delegate as! AppDelegate).persistentStoreCoordinator
        self.MOC.undoManager = nil //makes it go faster, apparently
        
        //set up map and its location
        mapView.delegate = self
        mapView.mapType = MKMapType.satellite //allow 3d approach
        let initialLocation = CLLocation(latitude: 54.233560, longitude: -4.523264) //centre on the Isle of Man
        mapView.centreMapOnLocation(location: initialLocation, regionRadius: 500000)
        
        //get all the stations
        let stationFetch = NSFetchRequest<Station>(entityName: "Station")
        do {
            let stationList = try self.MOC.fetch(stationFetch)
            for station in stationList {
                if (Int(station.northing!) > 0) && (Int(station.easting!) > 0) {
                    mapView.addAnnotation(station)
                }
            }
        }
        catch {
            //pass
        }
        
        //draw a train -> first one giving a real result
        let trainFetch = NSFetchRequest<Train>(entityName: "Train")
        do {
            let trainList = try self.MOC.fetch(trainFetch)
            var trainLines: [MKPolyline] = []
            var trainCount = 0
            for train in trainList {
                if trainCount > 100 {
                    break
                }
                let trainLine = train.routeLine()
                if trainLine != nil {
                    trainLines.append(trainLine!)
                }
                trainCount += 1
            }
            mapView.addOverlays(trainLines)
        }
        catch {
            //pass
        }
    }
    
    //determine how each annotation should be shown
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let annotation = annotation as? Station {
            let identifier = "stationmarker"
            var view: MKAnnotationView
            if let dequeuedView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKPinAnnotationView {
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
        if let overlay = overlay as? MKPolyline {
            let polylineRenderer = MKPolylineRenderer(polyline: overlay)
            polylineRenderer.strokeColor = NSColor.red
            polylineRenderer.lineWidth = 3
            return polylineRenderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

class TrainMapView: MKMapView {
    
    func centreMapOnLocation(location: CLLocation, regionRadius: CLLocationDistance) {
        let coordinateRegion = MKCoordinateRegionMakeWithDistance(location.coordinate, regionRadius * 2.0, regionRadius * 2.0)
        self.setRegion(coordinateRegion, animated: true)
    }
}
