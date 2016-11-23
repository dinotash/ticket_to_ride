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
        
        //draw all the station pairs
        let pairFetch: NSFetchRequest = NSFetchRequest<Pair>(entityName: "Pair")
        do {
            let pairList: [Pair] = try self.MOC.fetch(pairFetch)
            print("Pairs: " + String(pairList.count))
            var pairLines: [MKPolyline] = []
            for pair in pairList {
                let pairLine: MKPolyline? = pair.routeLine()
                if (pairLine != nil) {
                    pairLines.append(pairLine!)
                }
            }
            print("Pair lines: " + String(pairLines.count))
            mapView.addOverlays(pairLines)
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
            let polylineRenderer: MKPolylineRenderer = MKPolylineRenderer(polyline: overlay)
            polylineRenderer.strokeColor = NSColor.red
            polylineRenderer.lineWidth = 3
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
