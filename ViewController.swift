//
//  ViewController.swift
//  Badger - Increment the App Icon Badge when the App goes into the background.
//           (We don't need no stinkin' badges ... oh yes we do!)
//
//  Created by ByteSlinger 2018-01-08.
//  Copyright © 2018 ByteSlinger. All rights reserved.
//

import UIKit
import CoreLocation
import UserNotifications

let ME = "Badger"

class ViewController: UIViewController, UNUserNotificationCenterDelegate, CLLocationManagerDelegate {
    private var badgeEnabled = false
    private var timer: Timer! = nil
    private var badge = 0
    private var locationManager: CLLocationManager! = nil
    private var enableAlert = true
    private var authorized = false
    
    @IBOutlet weak var enableSwitch: UISwitch!
    @IBOutlet weak var badgeValue: UILabel!     // placed on upper right of appIconImage in storyboard
    @IBOutlet weak var appIconImage: UIImageView!
    
    let SPEW_ON = false      // set this to true for debugging messages in console
    func spew(_ msg: String) {
        if (SPEW_ON) {
            print(msg)
        }
    }
    
    // connected to enableSwitch in Main.storyboard
    @IBAction func enableBadgeUpdate(_ sender: UISwitch) {
        spew("enableBadgeUpdate()")
        
        if (requestNoficationAuthorization()) {
            self.badgeEnabled = self.enableSwitch.isOn
        } else {
            self.enableSwitch.isOn = false
            
            displayAuthorizationFailedMessage()
        }

        self.badge = 0
        
        updateDisplay()
    }
    
    // this is against the user interface guidelines, but it does work
    @objc func goToBackground() {
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
    
    override func viewDidLoad() {
        spew("viewWillDidLoad()")
        
        super.viewDidLoad()
        
        // allow the user to go to the background with a button
        // (against user interface guidelines but a neat trick for this app...)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Go To Background", style: .done, target: self, action: #selector(goToBackground))
        
        // setup my app observers to handle moving between foreground and background (and terminating)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: .UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: .UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate), name: .UIApplicationWillTerminate, object: nil)
        
        // make my "badge" rounded like the app icon badge
        self.badgeValue.layer.cornerRadius = 20
        self.badgeValue.layer.masksToBounds = true
        
        // get the app icon image for my image (larger than the app icon)
        self.appIconImage.image = UIApplication.shared.icon
        self.appIconImage.layer.cornerRadius = 20
        self.appIconImage.layer.masksToBounds = true
        
        updateBadge()   // initially set to 0, which clears it
        
        updateDisplay()
        
        if (!requestNoficationAuthorization()) {
            displayAuthorizationFailedMessage()
        }
    }
    
    // start the location manager so we are kept alive in the background
    func startLocationManager() {
        if (CLLocationManager.locationServicesEnabled() == false ||
            CLLocationManager.authorizationStatus() == CLAuthorizationStatus.denied) {
            self.locationManager = nil
            
            showAlert("Location Services must be set to ON and set to ALWAYS for the \(ME) app " +
                      "to be able to run in the background")
        } else {
            if (self.locationManager == nil) {
                // turn on LocationManager so we stay alive in the background
                self.locationManager = CLLocationManager()
                self.locationManager.requestAlwaysAuthorization()
                self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                self.locationManager.allowsBackgroundLocationUpdates = true     // the magic sauce...
                self.locationManager.pausesLocationUpdatesAutomatically = false
                self.locationManager.startUpdatingLocation()
            }
        }
    }
    
    func updateDisplay() {
        spew("updateDisplay()")
        
        if (self.enableAlert) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Disable Alerts", style: .done, target: self, action: #selector(disableAlerts))
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Enable Alerts", style: .done, target: self, action: #selector(enableAlerts))
        }
        
        self.enableSwitch.isOn = self.badgeEnabled
        
        self.badgeValue.isHidden = self.badge > 0 ? false : true
        
        self.badgeValue.text = "  \(self.badge)  "
    }
    
    // MARK:  - observer functions
    
    // when the app goes into the background, start updating the badge
    @objc func willResignActive() {
        spew("willResignActive()")
        
        updateBadge()           // set app icon badge to current value right away
        
        startLocationManager()  // checks to see if it's already started first
        
        if (authorized) {
            notify()                // send an alert to whatever is in the foreground
        
            startBadgeUpdate()      // start incrementing the app icon badge
        }
    }
    
    // when the app is coming into the foreground, cancel the badge updates
    @objc func willEnterForeground() {
        spew("willEnterForeground()")
        
        cancelBadgeUpdate(true)
    }
    
    // when the app terminates, clear the badge
    @objc func willTerminate() {
        spew("willTerminate()")
        
        disableAlerts()
        
        cancelBadgeUpdate(false)
    }
    
    // MARK: - badge handling functions
    
    func clearBadge() {
        // NOTE:  setting/clearing the badge does NOT work when the app is terminated
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    func updateBadge() {
        UIApplication.shared.applicationIconBadgeNumber = self.badge
    }
    
    @objc func incrementBadge() {
        self.badge += 1
        
        updateBadge()
    }
    
    // use a timer to increment and set the app icon badge
    func startBadgeUpdate() {
        spew("startBadgeUpdate() - badgEnabled = \(self.badgeEnabled)")
        
        // just incase the timer was left running
        if (self.timer != nil) {
            self.timer!.invalidate()
            self.timer = nil
        }
        
        if (self.badgeEnabled) {
            self.timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(incrementBadge), userInfo: nil, repeats:true)
        }
    }
    
    func cancelBadgeUpdate(_ updateTheDisplay: Bool) {
        spew("cancelBadgeUpdate()")
        
        if (self.timer != nil) {
            self.timer!.invalidate()
        }
        
        clearBadge()        // incase we go away, badge is clear
        
        if (updateTheDisplay) {
            updateDisplay()     // show the current badge value
        }
    }
    
    // MARK:  - notification handling functions
    
    func displayAuthorizationFailedMessage() {
        self.showAlert("Allow Notifications for the \(ME) app have been turned OFF in Settings. " +
            "You must turn it ON for the \(ME) app to function.")
    }
    
    func requestNoficationAuthorization() -> Bool {
        spew("requestNoficationAuthorization()")
        
        let center = UNUserNotificationCenter.current()
        var result = true
        
        center.requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            if granted {
                result = true
            } else {
                self.spew("requestNoficationAuthorization() failed!")
                result = false
            }
        }
        
        self.authorized = result
        
        return result
    }
    
    func cancelAlerts() {
        spew("cancelAlerts()")
        
        // incase there is an alert lurking out there, remove them all
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [UUID().uuidString])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [UUID().uuidString])
    }
    
    @objc func enableAlerts() {
        spew("enableAlert()")
        
        self.enableAlert = true
        
        updateDisplay() // change bar button text
    }
    
    @objc func disableAlerts() {
        spew("disableAlerts()")
        
        self.enableAlert = false
        
        if (UIApplication.shared.applicationState == .active) {
            updateDisplay()
        }
    }
    
    // setup notification "buttons"
    func registerCategories() {
        spew("registerCategories()")
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        let open = UNNotificationAction(identifier: "open", title: "Open the app…", options: .foreground)
        let disable = UNNotificationAction(identifier: "disable", title: "Disable This Alert", options: .destructive)
        let category = UNNotificationCategory(identifier: "alert", actions: [open,disable], intentIdentifiers: [])
        
        center.setNotificationCategories([category])
    }
    
    // send a notification request
    func notify() {
        if (authorized && enableAlert) {
            
            spew("notify()")
            
            cancelAlerts()  // any existing alerts
            
            let onOffMsg = self.badgeEnabled ? "On" : "Off"
            let center = UNUserNotificationCenter.current()
            
            registerCategories()
            
            let content = UNMutableNotificationContent()
            content.title = "I am in the background..."
            content.body = "Badge updates are " + onOffMsg
            content.categoryIdentifier = "alert"
            content.userInfo = ["customData": "notify"]
            //content.sound = UNNotificationSound.default() ... annoying

            if (!self.badgeEnabled) {
                content.badge = 0   // clears app icon badge
            }
            
            if let attachment = UNNotificationAttachment.create(identifier: UIApplication.shared.uniqueId,
                                                                image: UIApplication.shared.icon!, options: nil) {
                content.attachments = [attachment]
            }
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            center.add(request)
        }
    }
    
    // UNNotificationCenterDelegate method
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // pull out the buried userInfo dictionary
        let userInfo = response.notification.request.content.userInfo
        
        if let customData = userInfo["customData"] as? String {
            spew("userNotificationCenter.didReceive() - received: \(customData), actionId: \(response.actionIdentifier)")
            
            switch response.actionIdentifier {
            case UNNotificationDefaultActionIdentifier:
                // the user swiped to unlock
                spew("Default user tap...")
                
            case "show":
                // the user tapped our "Open the app…" bit
                spew("Open the app…")
                
            case "disable":
                spew("User disabled alerts...")
                disableAlerts()
                
            default:
                break
            }
        }
        
        // you must call the completion handler when you're done
        completionHandler()
    }
    
    // show a popup message
    func showAlert (_ message: String) {
        let alert = UIAlertController(
            title: "\(ME) Alert",
            message: message,
            preferredStyle: UIAlertControllerStyle.alert);
        
        let alertOKAction = UIAlertAction(title:"OK", style: UIAlertActionStyle.default,
                                          handler: { action in })
        
        alert.addAction(alertOKAction);
        
        self.present(alert, animated: true, completion: nil);
    }
}
