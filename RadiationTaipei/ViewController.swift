//
//  ViewController.swift
//  APITest
//
//  Created by Ka Ho on 30/5/2016.
//  Copyright © 2016 Ka Ho. All rights reserved.
//

import UIKit
import Alamofire
import SwiftyJSON
import PKHUD
import ScrollableGraphView
import MapKit
import CoreLocation

class ViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var graphRefFrame: UIView!
    @IBOutlet weak var currentStationLabel: UILabel!
    @IBOutlet weak var runnongFooterLabel: UILabel!
    let locationManager = CLLocationManager()
    var graphView = ScrollableGraphView()
    var stationInfo:[[String:String]] = []
    var allGammaInfo:[JSON] = []
    var dataReady = false
    var locationDisable = true
    var initialShown = false // for simulator permission open but no actual location
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        mapView.delegate = self
        view.alpha = 0.2
        HUD.show(.LabeledProgress(title: "請稍候", subtitle: "監測站資料載入中"))

        getStationInfo { (result) in
            result ? self.markAnnotation() : ()
            HUD.show(.LabeledProgress(title: "請稍候", subtitle: "即時數據載入中"))
            self.stationRealTimeData { (result) in
                if result {
                    self.dataReady = true
                    if self.locationDisable || !self.initialShown {
                        self.potSpecificStationData(self.stationInfo[0]["sta"]!, stationName: self.stationInfo[0]["name"]!)
                        self.view.alpha = 1
                    }
                }
            }
        }
    }
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        if status == .AuthorizedWhenInUse {
            locationManager.startUpdatingLocation()
            locationDisable = false
        }
    }
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if dataReady {
            locationManager.stopUpdatingLocation()
            dataReady = false
            initialShown = true
            var closestDistance:Double = 0
            var closestStation = ""
            var closestStationName = ""
            for station in stationInfo {
                let currentDistance = locations.first?.distanceFromLocation(CLLocation(latitude: Double(station["lat"]!)!, longitude: Double(station["lng"]!)!))
                if closestDistance == 0 || currentDistance < closestDistance {
                    closestDistance = currentDistance!
                    closestStation = station["sta"]!
                    closestStationName = station["name"]!
                }
            }
            potSpecificStationData(closestStation, stationName: closestStationName)
            view.alpha = 1
        }
    }

    func getStationInfo(completion: (result:Bool) -> Void) {
        Alamofire.request(.GET, "http://data.taipei/opendata/datalist/apiAccess?scope=resourceAquire&rid=ae4e05cc-8ccf-43ac-b911-3099418bd22a").responseJSON { (response) in
            let stations = JSON(response.result.value!)["result"]["results"].arrayValue
            for station in stations {
                self.stationInfo.append(["sta":"00\(station["STA_NO"].stringValue)", "name":"\(station["測站名稱"].stringValue)監測站", "address":station["地址"].stringValue, "lat":station["緯度"].stringValue, "lng":station["經度"].stringValue])
            }
            completion(result: true)
        }
    }
    
    func stationRealTimeData(completion: (result: Bool) -> Void) {
        Alamofire.request(.GET, "https://tpdep.blob.core.windows.net/techdep/techdep_gamma5m.gz").responseJSON { (data) in
            self.allGammaInfo = JSON(data.result.value!).arrayValue
            completion(result: true)
        }
    }
    
    func potSpecificStationData(stationNo: String, stationName: String) {
        var rawData:[[String:AnyObject]] = []
        var data:[Double] = []
        var labels:[String] = []

        for each in self.allGammaInfo where each["STA_NO"].stringValue == stationNo {
            rawData.append(["timeDistance":self.nsdateFromNowInterval(each["DTIME"].stringValue), "time":self.nsdateToReadable(each["DTIME"].stringValue), "rate":each["DOSERATE"].doubleValue])
        }
        rawData.sortInPlace({ $1["timeDistance"] as! Double > $0["timeDistance"] as! Double})

        for loop in rawData {
            data.append(loop["rate"] as! Double)
            labels.append((loop["time"] as! String).containsString("00分") ? (loop["time"] as! String) : "")
        }
        
        let highestRate = data.maxElement()
        let highestTime = "\(rawData[data.indexOf(highestRate!)!]["time"]!)"
        let lowestRate = data.minElement()
        let lowestTime = "\(rawData[data.indexOf(lowestRate!)!]["time"]!)"
        let unit = "微西弗/時(μSv/h)"
        let extraSpace = String(count: 30, repeatedValue: Character(" "))

        dispatch_async(dispatch_get_main_queue()) {
            self.graphView.removeFromSuperview()
            let rect = CGRectMake(0, 100, self.graphRefFrame.frame.width, self.graphRefFrame.frame.height)
            self.graphView = self.createDarkGraph(rect)
            self.graphView.setData(data, withLabels: labels)
            self.view.addSubview(self.graphView)
            self.currentStationLabel.text = "\(stationName)"
            self.runnongFooterLabel.text = "\(stationName)最新讀數: \(data[0])\(unit)      7天最高: \(String(format:"%.3f", highestRate!))(\(highestTime))      7天最低: \(String(format:"%.3f", lowestRate!))(\(lowestTime))\(self.view.frame.width > 1000 ? extraSpace : "")"
            HUD.hide()
        }
    }
    
    override func didRotateFromInterfaceOrientation(fromInterfaceOrientation: UIInterfaceOrientation) {
        let rect = CGRectMake(0, 100, self.graphRefFrame.frame.width, self.graphRefFrame.frame.height)
        self.graphView.frame = rect
    }
    
    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        self.graphView.frame = CGRectMake(0, 0, 0, 0)
    }

    func markAnnotation() {
        for station in stationInfo {
            let anotation = MKPointAnnotation()
            anotation.coordinate = CLLocationCoordinate2D(latitude: Double(station["lat"]!)!, longitude: Double(station["lng"]!)!)
            anotation.title = "\(station["name"]!)"
            anotation.subtitle = "\(station["address"]!)"
            mapView.addAnnotation(anotation)
        }
        mapView.showAnnotations(mapView.annotations, animated: true)
    }
    
    func mapView(mapView: MKMapView, didSelectAnnotationView view: MKAnnotationView) {
        for station in stationInfo {
            if let address = view.annotation!.subtitle, let name = view.annotation!.title {
                station["address"]! == address ? confirmToShow(name!, targetNo: station["sta"]!) : ()
            }
        }
    }
    
    func confirmToShow(stationName: String, targetNo: String) {
        let alertController = UIAlertController(title: "確認顯示數據", message: "顯示\(stationName)輻射數據？", preferredStyle: .Alert)
        let alertAction = UIAlertAction(title: "是", style: .Default) { (action) in
            dispatch_async(dispatch_get_main_queue(), {
                HUD.show(.LabeledProgress(title: "請稍候", subtitle: "監測站資料載入中"))
            })
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), {
                self.potSpecificStationData(targetNo, stationName: stationName)
                })
        }
        let alertCancel = UIAlertAction(title: "否", style: .Cancel, handler: nil)
        alertController.addAction(alertAction)
        alertController.addAction(alertCancel)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    private func createDarkGraph(frame: CGRect) -> ScrollableGraphView {
        let graphView = ScrollableGraphView(frame: frame)
        graphView.backgroundFillColor = UIColor.blackColor()
        graphView.referenceLineNumberOfDecimalPlaces = 3
        graphView.shouldAdaptRange = true
        graphView.lineWidth = 2
        graphView.lineColor = UIColor.redColor()
        graphView.shouldFill = true
        graphView.fillType = ScrollableGraphViewFillType.Gradient
        graphView.fillColor = UIColor.colorFromHex("#555555")
        graphView.fillGradientType = ScrollableGraphViewGradientType.Linear
        graphView.fillGradientStartColor = UIColor.orangeColor()
        graphView.fillGradientEndColor = UIColor.orangeColor()
        graphView.dataPointSpacing = 10
        graphView.dataPointSize = 4
        graphView.dataPointFillColor = UIColor.blueColor()
        graphView.referenceLineLabelFont = UIFont.boldSystemFontOfSize(8)
        graphView.referenceLineColor = UIColor.whiteColor().colorWithAlphaComponent(0.2)
        graphView.referenceLineLabelColor = UIColor.whiteColor()
        graphView.dataPointLabelColor = UIColor.whiteColor()
        return graphView
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func nsdateFromNowInterval(source: String) -> Double {
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return NSDate().timeIntervalSinceDate(dateFormatter.dateFromString(source)!)
    }
    
    func nsdateToReadable(source: String) -> String {
        // api wrong implementation on time standard, temporary edit
        let editedSource = source.stringByReplacingOccurrencesOfString(".000Z", withString: "+0800")
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZ"
        let outputFormatter = NSDateFormatter()
        outputFormatter.dateFormat = "MM月dd日HH時mm分"
        return outputFormatter.stringFromDate(dateFormatter.dateFromString(editedSource)!)
    }
}
