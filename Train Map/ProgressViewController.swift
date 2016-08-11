//
//  ProgressViewController.swift
//  Train Map
//
//  Created by Tom Curtis on 5 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Foundation
import Cocoa

class ProgressViewController: NSViewController {
    
    @IBOutlet weak var importController: ImportViewController!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var progressLabel: NSTextField!
    
    override func viewDidLoad() {        
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        self.progressBar.indeterminate = true
        self.progressBar.minValue = 0
        self.progressBar.maxValue = 1
        self.progressBar.startAnimation(nil)
        self.progressLabel.stringValue = "Beginning import..."
    }
    
    override var representedObject: AnyObject? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func cancelImports(sender: AnyObject) {
        importController.pendingOperations.importQueue.cancelAllOperations()
        super.dismissController(nil)
    }
    
    //tell the main thread to update the progress in inderminate fashion
    func updateIndeterminate(label: String) {
        dispatch_async(dispatch_get_main_queue(), {
            self.progressLabel.stringValue = label
            self.progressBar.indeterminate = true
            self.progressBar.startAnimation(nil)
            })
    }
    
    //update a determinate progress bar -> assumes doubleValue is between previously set max and min values
    func updateDeterminate(label: String, doubleValue: Double, updateBar: Bool) {
        dispatch_async(dispatch_get_main_queue(), {
            self.progressLabel.stringValue = label
            if (updateBar) {
                self.progressBar.indeterminate = false
                self.progressBar.stopAnimation(nil)
                self.progressBar.doubleValue = doubleValue
            }
        })
    }
    
}