//
//  ViewController.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 24 Jul 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

import Cocoa


class ImportViewController: NSViewController {
    
    var progressViewController: ImportProgressViewController?
    var pendingOperations: PendingOperations!
    
    // Retreive the managedObjectContext from AppDelegate
    let mainMOC = (NSApplication.sharedApplication().delegate as! AppDelegate).managedObjectContext
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override var representedObject: AnyObject? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    //Find and load new data set
    @IBAction func loadNewData(sender: AnyObject) {
    
        //data file types to use
        let dataFileTypes = ["alf", "mca", "msn", "ztr"]
     
        //file chooser dialog
        let dialog = NSOpenPanel()
        dialog.title                   = "Select a data file"
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = false
        dialog.canChooseDirectories    = true
        dialog.canCreateDirectories    = true
        dialog.allowsMultipleSelection = false
        dialog.allowedFileTypes        = dataFileTypes

        if (dialog.runModal() == NSModalResponseOK) {
            dialog.performClose(nil)
            
            //display the progress dialog box
            if let pvc = storyboard!.instantiateControllerWithIdentifier("importProgressViewController") as? ImportProgressViewController {
                self.progressViewController = pvc
                presentViewControllerAsSheet(self.progressViewController!)
                self.progressViewController!.importController = self
            }
            
            //now launch the importing operation
            self.pendingOperations = PendingOperations()
            let ttisImport = ttisImporter(chosenFile: dialog.URL!, progressViewController: progressViewController)
            ttisImport.completionBlock = {
                if ttisImport.cancelled {
                    return
                }
                //close the progress view controller and let the user know
                dispatch_async(dispatch_get_main_queue(), {
                    //do stuff to refresh main display
                    self.progressViewController?.dismissController(self)
                    let alert = NSAlert();
                    alert.alertStyle = NSAlertStyle.InformationalAlertStyle
                    alert.messageText = "Import complete";
                    alert.informativeText = "Successfully completed import of new data!"
                    alert.runModal();
                })
                self.view.window!.close() //close the import window
                
            }
            self.pendingOperations.importsInProgress.append(ttisImport) //add to queue to keep track of it
            self.pendingOperations.importQueue.addOperation(ttisImport)
        }
        else {
            // User clicked on "Cancel"
            return
        }
    }
    
    @IBAction func cancelImports(sender: AnyObject) {
        if (self.pendingOperations != nil) {
            self.pendingOperations.importsInProgress = []
            self.pendingOperations.importQueue.cancelAllOperations()
        }
        self.view.window!.close()
    }
    
}