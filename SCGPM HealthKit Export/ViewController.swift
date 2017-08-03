//
//  ViewController.swift
//  SCGPM HealthKit Export
//
//  Created by Isaac Liao on 4/5/17.
//  Copyright © 2017 SCGPM. All rights reserved.
//

import UIKit
import HealthKit

class ViewController: UIViewController {
    
    let healthStore = HKHealthStore()
    let stepCountType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!
    let heartRateType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!
    let sortByTime = NSSortDescriptor(key:HKSampleSortIdentifierEndDate, ascending:true)
    let userCalendar = Calendar.current
    
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusText: UITextView!
    @IBOutlet weak var memoryLabel: UILabel!
    @IBOutlet weak var diskSpaceLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.statusText.layoutManager.allowsNonContiguousLayout = false
        self.statusText.addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
        _ = Timer.scheduledTimer(timeInterval: 1.0, target:self, selector: #selector(self.updateMemoryDisplay), userInfo: nil, repeats: true
        )
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        DispatchQueue.main.async {
            self.progressView.setProgress(0.0, animated: false)
        }
        if (HKHealthStore.isHealthDataAvailable()){
            self.healthStore.requestAuthorization(toShare: nil, read:[heartRateType,stepCountType], completion:{(success, error) in
                    self.queryAndDisplaySources()
                }
            )
        }
    }
    func queryAndDisplaySources() {
        let query = HKSourceQuery(sampleType: self.heartRateType, samplePredicate:nil) {
            query, sources, error in
            if error != nil {
                // Perform Proper Error Handling Here...
                print("*** An error occured while gathering the sources for heart rate data. \(error!.localizedDescription) ***")
                abort()
            }
            
            for object: AnyObject in sources! {
                if let source = object as? HKSource {
                    DispatchQueue.main.async {
                        self.statusText.text = self.statusText.text + "Source: \(String(describing:source))\n"
                        print("Source: \(String(describing:source))\n")
                    }
                    self.queryAndExportHeartRateData(source:source)
                }
            }
        }
        self.healthStore.execute(query)

    }
    func queryAndExportHeartRateData(source: HKSource?) {
        var sourcePredicate: NSPredicate?
        if source != nil {
            sourcePredicate = HKQuery.predicateForObjects(from:source!)
        }
        let query = HKSampleQuery(sampleType: self.heartRateType, predicate:sourcePredicate, limit:1, sortDescriptors:[self.sortByTime], resultsHandler:{ (query, results, error) in
            guard let returnedResults = results, returnedResults.count > 0 else {
                DispatchQueue.main.async {
                    var sourceText = ""
                    if source != nil {
                        sourceText = " for source \(source!.name)"
                    }
                    self.statusText.text = self.statusText.text + "\nNo heart rate samples found\(sourceText)"
                    print("No heart rate samples found\(sourceText)")
                }
                return
            }
            guard let oldestSample:HKSample = returnedResults[0] else {
                fatalError("Error: \(error!.localizedDescription)")
            }
            let startDate = oldestSample.startDate
            var endDate:Date! = self.userCalendar.date(byAdding: DateComponents(month:1), to: startDate)
            endDate = self.userCalendar.date(bySetting: Calendar.Component.day, value: 1, of: endDate)
            endDate = self.userCalendar.date(bySetting: Calendar.Component.hour, value: 0, of: endDate)
            endDate = self.userCalendar.date(bySetting: Calendar.Component.minute, value: 0, of: endDate)
            endDate = self.userCalendar.date(bySetting: Calendar.Component.second, value: 0, of: endDate)
            endDate = self.userCalendar.date(bySetting: Calendar.Component.nanosecond, value: 0, of: endDate)
            self.exportHeartRateData(startDate:startDate,endDate:endDate,sourcePredicate:sourcePredicate,sourceName:source?.name,sourceID:source?.bundleIdentifier)
        })
        self.healthStore.execute(query)
    }

    func exportHeartRateData(startDate: Date, endDate: Date, sourcePredicate: NSPredicate?, sourceName: String?, sourceID: String?) {
        let intervalPredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        var combinedSourceIntervalPredicate = intervalPredicate
        if sourcePredicate != nil {
            combinedSourceIntervalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates:[sourcePredicate!,intervalPredicate])
        }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/YYYY"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "YYYY-MM"
        monthFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        DispatchQueue.main.async {
            self.statusText.text = self.statusText.text + "\nQuerying \(dateFormatter.string(from:startDate)) - \(dateFormatter.string(from:endDate))..."
            print("Querying \(dateFormatter.string(from:startDate)) - \(dateFormatter.string(from:endDate))...")
        }
        
        let query = HKSampleQuery(sampleType:heartRateType, predicate:combinedSourceIntervalPredicate, limit:HKObjectQueryNoLimit, sortDescriptors:[sortByTime], resultsHandler:{(query, results, error) in
            guard var results = results else { return }
            var sampleCount: Float = 0.0
            DispatchQueue.main.async {
                self.statusText.text = self.statusText.text + "\nParsing \(results.count) heart rate samples..."
                print("Parsing \(results.count) heart rate samples...")
            }
            
            var csvString = "StartDate\tStartTime\tEndDate\tEndTime\tHeartRate(BPM)\tDevice\tMetadata\n"
            for quantitySample in results {
                sampleCount += 1
                let progress: Float = sampleCount / Float(results.count)
                if (sampleCount.truncatingRemainder(dividingBy: 100) == 0) {
                    DispatchQueue.main.async {
                        self.progressView.setProgress(progress, animated: true)
                    }
                }
                let hkQuantitySample:HKQuantitySample = quantitySample as! HKQuantitySample
                let quantity = (quantitySample as! HKQuantitySample).quantity
                let heartRateUnit = HKUnit(from: "count/min")
                let device = hkQuantitySample.device != nil ? String(describing:hkQuantitySample.device!) : "nil"
                let metadata = hkQuantitySample.metadata != nil ? String(describing:hkQuantitySample.metadata!) : "nil"
                
                //                        csvString.extend("\(quantity.doubleValueForUnit(heartRateUnit)),\(timeFormatter.stringFromDate(quantitySample.startDate)),\(dateFormatter.stringFromDate(quantitySample.startDate))\n")
                //                        println("\(quantity.doubleValueForUnit(heartRateUnit)),\(timeFormatter.stringFromDate(quantitySample.startDate)),\(dateFormatter.stringFromDate(quantitySample.startDate))")
                csvString += "\(dateFormatter.string(from: quantitySample.startDate))\t\(timeFormatter.string(from: quantitySample.startDate))\t\(dateFormatter.string(from: quantitySample.endDate))\t\(timeFormatter.string(from: quantitySample.endDate))\t\(quantity.doubleValue(for: heartRateUnit))\t\(device)\t\(metadata)\n"
                //print("\(timeFormatter.string(from: quantitySample.startDate)),\(dateFormatter.string(from: quantitySample.startDate)),\(quantity.doubleValue(for: heartRateUnit))")
            }
            
            do {
                let documentsDir = try FileManager.default.url(for: .documentDirectory, in:.userDomainMask, appropriateFor:nil, create:true)
                var filename = "heartrate-\(monthFormatter.string(from:startDate)).tsv"
                if sourceName != nil {
                    filename = sourceName! + "-" + sourceID! + "-" + filename
                }
                DispatchQueue.main.async {
                    self.statusText.text = self.statusText.text + "\nWriting \(filename)..."
                    print("Writing \(filename)...")
                }
                let path = documentsDir.appendingPathComponent(filename)
                try csvString.write(to:path, atomically:true, encoding:String.Encoding.unicode)
                csvString = ""
                results = []
                if (endDate <= Date())
                {
                    let newStartDate = endDate
                    let newEndDate = self.userCalendar.date(byAdding: DateComponents(month:1), to: endDate)
                    self.exportHeartRateData(startDate:newStartDate,endDate:newEndDate!,sourcePredicate:sourcePredicate, sourceName:sourceName, sourceID:sourceID)
                } else {
                    DispatchQueue.main.async {
                        self.statusText.text = self.statusText.text + "\nDone exporting from " + sourceName!
                        print("Done exporting from " + sourceName!)
                    }
                }

            }
            catch {
                print(error)
            }
        })
        self.healthStore.execute(query)
        
    }
    
    func getMemoryUsed() -> UInt64
    {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info))/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info)
        {
            task_info(mach_task_self_,
                      task_flavor_t(MACH_TASK_BASIC_INFO),
                      $0.withMemoryRebound(to: Int32.self, capacity: 1) { zeroPtr in
                        task_info_t(zeroPtr) },
                      &count)
        }
        
        if kerr == KERN_SUCCESS {
            //print("Memory in use (in bytes): \(info.resident_size)")
            return info.resident_size
        }
        else {
            print("Error with task_info(): " +
                (String.init(validatingUTF8: mach_error_string(kerr)) ?? "unknown error"))
            return 0
        }
    }
    
    func updateMemoryDisplay() {
        DispatchQueue.main.async {
            let megsTotalRAM = ProcessInfo.processInfo.physicalMemory/(1024 * 1024)
            let megsUsedRAM = self.getMemoryUsed()/(1024*1024)
            self.memoryLabel.text = "\(megsUsedRAM) of \(megsTotalRAM) MB memory used"
            let gigsUsedDisk = DiskStatus.GBFormatter(DiskStatus.usedDiskSpaceInBytes)
            let gigsTotalDisk = DiskStatus.GBFormatter(DiskStatus.totalDiskSpaceInBytes)
            self.diskSpaceLabel.text = "\(gigsUsedDisk) of \(gigsTotalDisk) GB disk space used"
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        var bottom = self.statusText.contentSize.height - self.statusText.frame.size.height
        if bottom < 0 {
            bottom = 0
        }
        if self.statusText.contentOffset.y != bottom {
            self.statusText.setContentOffset(CGPoint(x: 0, y: bottom), animated: true)
        }
    }
    /*
    func exportStepData() {
        let sortByTime = NSSortDescriptor(key:HKSampleSortIdentifierEndDate, ascending:false)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/YYYY"


        let query = HKSampleQuery(sampleType:stepCountType, predicate:nil, limit:15000, sortDescriptors:[sortByTime], resultsHandler:{(query, results, error) in
        guard let results = results else { return }
        var sampleCount: Float = 0.0
        self.progressView.setProgress(0.0, animated: false)
        var csvString = "Time,Date,StepCount,DeviceName,DeviceManufacturer,DeviceModel\n"
        for quantitySample in results {
        let hkQuantitySample:HKQuantitySample = quantitySample as! HKQuantitySample
        let quantity = hkQuantitySample.quantity
        let stepCountUnit = HKUnit(from: "count")
        let device = hkQuantitySample.device
        
        //                        csvString.extend("\(quantity.doubleValueForUnit(heartRateUnit)),\(timeFormatter.stringFromDate(quantitySample.startDate)),\(dateFormatter.stringFromDate(quantitySample.startDate))\n")
        //                        println("\(quantity.doubleValueForUnit(heartRateUnit)),\(timeFormatter.stringFromDate(quantitySample.startDate)),\(dateFormatter.stringFromDate(quantitySample.startDate))")
        csvString += "\(timeFormatter.string(from: quantitySample.startDate)),\(dateFormatter.string(from: quantitySample.startDate)),\(quantity.doubleValue(for: stepCountUnit)),\(device?.name ?? "nil"),\(device?.manufacturer ?? "nil"),\(device?.model ?? "nil")\n"
        sampleCount += 1
        let progress: Float = sampleCount / Float(query.limit)
        DispatchQueue.main.async {
            self.progressView.setProgress(progress, animated: true)
        }
        print(progress)
        //print("\(timeFormatter.string(from: quantitySample.startDate)),\(dateFormatter.string(from: quantitySample.startDate)),\(quantity.doubleValue(for: stepCountUnit)),\(device?.name ?? "nil"),\(device?.manufacturer ?? "nil"),\(device?.model ?? "nil")")
        }
        
        do {
        let documentsDir = try FileManager.default.url(for: .documentDirectory, in:.userDomainMask, appropriateFor:nil, create:true)
        let path = documentsDir.appendingPathComponent("stepcountdata.csv")
        try csvString.write(to:path, atomically:true, encoding:String.Encoding.ascii)
        }
        catch {
        print("Error occured")
        }
        })
        self.healthStore.execute(query)
    }
    */
}
