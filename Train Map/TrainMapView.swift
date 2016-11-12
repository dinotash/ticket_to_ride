//
//  TrainMapView.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 12 Nov 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa
import MapKit

class TrainMapView: MKMapView {
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.mapType = MKMapType.satellite
    }
    
}
