//
//  ProgressViewController.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 5 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

class ProgressViewController: NSViewController {
    
    @IBOutlet weak var parentController: NSViewController!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var progressLabel: NSTextField!
    
    override func viewDidLoad() {        
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        self.progressBar.isIndeterminate = true
        self.progressBar.minValue = 0
        self.progressBar.maxValue = 1
        self.progressBar.startAnimation(nil)
        self.progressLabel.stringValue = "Beginning import..."
    }
    
    //tell the main thread to update the progress in inderminate fashion
    func updateIndeterminate(_ label: String) {
        DispatchQueue.main.async(execute: {
            self.progressLabel.stringValue = label
            self.progressBar.isIndeterminate = true
            self.progressBar.startAnimation(nil)
            })
    }
    
    //update a determinate progress bar -> assumes doubleValue is between previously set max and min values
    func updateDeterminate(_ label: String, doubleValue: Double, updateBar: Bool) {
        DispatchQueue.main.async(execute: {
            self.progressLabel.stringValue = label
            if (updateBar) {
                self.progressBar.isIndeterminate = false
                self.progressBar.stopAnimation(nil)
                self.progressBar.doubleValue = doubleValue
            }
        })
    }
}

class ImportProgressViewController: ProgressViewController {
    @IBOutlet weak var importController: ImportViewController!
    
    @IBAction func cancelImports(_ sender: AnyObject) {
        self.updateIndeterminate("Cancelling import...")
        importController.pendingOperations.importQueue.cancelAllOperations()
        while (importController.pendingOperations.importQueue.operationCount > 0) {
            //wait for cancellation to actually happen
        }
        self.importController.dismissViewController(self)
    }
}
