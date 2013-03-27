//
//  WAViewController.m
//  WWDCAlert
//
//  Created by Rahul Matta on 3/19/13.
//  Copyright (c) 2013 RMatta. All rights reserved.
//

#import "WARefreshViewController.h"

#import <CoreLocation/CoreLocation.h>

#import "AFHTTPRequestOperation.h"
#import "AFHTTPClient.h"

#define kCacheKey @"LastFetchedWWDCWebPage"
#define kLastAccessDate @"LastAccessedDate"
#define kRefreshRate 45

@interface WARefreshViewController () <CLLocationManagerDelegate>

@property (nonatomic, strong) IBOutlet UIButton *refreshButton;
@property (nonatomic, strong) IBOutlet UIWebView *webView;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *activityView;
@property (nonatomic, strong) IBOutlet UILabel *dateLabel;
@property (nonatomic, strong) NSString *lastFetchedWebPage;
@property (nonatomic, strong) NSDate *lastAccessedDate;
@property (nonatomic, assign) BOOL restartBackgrounding;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic, strong) NSURL *url;

@end

@implementation WARefreshViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.restartBackgrounding = NO;
    self.locationManager = [CLLocationManager new];
    self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    self.locationManager.distanceFilter = 100;
    self.locationManager.delegate = self;
    
    self.dateLabel.text = @"";
    self.url = [NSURL URLWithString:@"https://developer.apple.com/wwdc/"];
    //    self.url = [NSURL URLWithString:@"http://techcrunch.com"]; //for testing
    
    self.lastFetchedWebPage = [[NSUserDefaults standardUserDefaults] objectForKey:kCacheKey];
    self.lastAccessedDate = [[NSUserDefaults standardUserDefaults] objectForKey:kLastAccessDate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startUpdatingLocation]; //just to get the location permissions out of the way
    [self refresh];
}

-(void)viewWillLayoutSubviews {
    self.activityView.center = self.webView.center;
}

- (IBAction)refresh {
    NSLog(@"Refreshing...");

    self.activityView.hidden = NO;

	self.lastFetchedWebPage = nil;
	self.lastAccessedDate = nil;
	
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kCacheKey];
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kLastAccessDate];

	
    NSURLRequest *request = [NSURLRequest requestWithURL:self.url];

    AFHTTPClient *client = [AFHTTPClient new];
    AFHTTPRequestOperation *operation =
    [client HTTPRequestOperationWithRequest:request
                                    success:^(AFHTTPRequestOperation *operation, id responseObject) {
                                        [self handlePageLoad:responseObject];
                                    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                        [self handleFailureToLoadPage:error];
                                    }];
    [operation start];
    
}

- (void)saveCurrentData {
    [[NSUserDefaults standardUserDefaults] setObject:self.lastFetchedWebPage forKey:kCacheKey];
    [[NSUserDefaults standardUserDefaults] setObject:self.lastAccessedDate forKey:kLastAccessDate];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)handlePageLoad:(NSData *)responseObject {
    NSString *newPage = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
    
    if (self.lastFetchedWebPage && self.lastAccessedDate && ![newPage isEqualToString:self.lastFetchedWebPage]) {
        [self alert:NO];
    }

	if ([newPage rangeOfString:@"wwdc2012-june"].location == NSNotFound) {
		[self alert:NO];
		[self alert:NO];
		[self alert:NO];
	}
    
    self.lastFetchedWebPage = newPage;
    self.lastAccessedDate = [NSDate date];
    [self.webView loadHTMLString:self.lastFetchedWebPage baseURL:self.url];
    self.dateLabel.text = [NSString stringWithFormat:@"Last checked on: %@",    
                           [NSDateFormatter localizedStringFromDate:self.lastAccessedDate
                                                          dateStyle:NSDateFormatterShortStyle
                                                          timeStyle:NSDateFormatterMediumStyle]];
    self.activityView.hidden = YES;
    [self saveCurrentData];

}

- (void)handleFailureToLoadPage:(NSError *)error {
    self.activityView.hidden = YES;
	NSLog(@"Error loading page: %@", error);
	
	// Do not disturb during network timeouts/failues, but do alert on 404s incase the page is moved.
	// Sadly NSUnderlyingErrorKey is nil so we need to parse the description. 
	if ([error.description rangeOfString:@"got 404"].location != NSNotFound) {
		[self alert:YES];
	}
}

- (void)alert:(BOOL)forErrorToLoad {
    NSString *msg = @"Hurry! Get your WWDC ticket now!";
    if (forErrorToLoad) {
        msg = @"Error loading WWDC page!";
    }
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        [self showAlert:msg];
    } else {
        [self notify:msg];
    }
}

- (void)showAlert:(NSString *)msg {
    [[[UIAlertView alloc] initWithTitle:nil
                                message:msg 
                               delegate:nil cancelButtonTitle:@"OK"
                      otherButtonTitles:nil] show];

}

- (void)notify:(NSString *)msg {
    UILocalNotification *notification = [UILocalNotification new];
    notification.alertBody = msg;
    notification.alertAction = @"OK";
    notification.applicationIconBadgeNumber = 1;
    notification.fireDate = nil;
    notification.soundName = UILocalNotificationDefaultSoundName;
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

- (void)startUpdatingLocation {
    [self.locationManager startUpdatingLocation];
}

- (void)stopUpdatingLocation {
    if (self.restartBackgrounding) {
        [self startBackgrounding];
    }
    NSLog(@"Stopping location update");
    [self.locationManager stopUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    NSLog(@"Latest location is %@", locations[0]);
    [self stopUpdatingLocation];
}

- (void)stopBackgrounding {
    [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
    self.bgTask = UIBackgroundTaskInvalid;
}

- (void)startBackgrounding {
    
    UIApplication* app = [UIApplication sharedApplication];
    
    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        //This is to be able to come back into backgrounding
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            NSLog(@"bgTask expired; restarting...");
            self.restartBackgrounding = YES;
            [self startUpdatingLocation];
        }
    }];
    
    self.restartBackgrounding = NO;
    
    // Start the long-running task and return immediately.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        while (self.bgTask != UIBackgroundTaskInvalid) {
            
            @autoreleasepool {
                
                [self performSelectorOnMainThread:@selector(refresh) withObject:nil waitUntilDone:NO];
                
                NSTimeInterval cushionedSleepTime = app.backgroundTimeRemaining - 60; //wake up 60s before expiration
                
                NSLog(@"App's remaining bg time is %f +60s", cushionedSleepTime);
                
                if (cushionedSleepTime > kRefreshRate) {
                    cushionedSleepTime = kRefreshRate; //wake up every 2 mins to refresh
                }
                
                cushionedSleepTime = lround(cushionedSleepTime);
                
                NSLog(@"Will sleep for %fs", cushionedSleepTime);
                
                if (cushionedSleepTime > 0) {
                    sleep(cushionedSleepTime);
                } else {
                    NSLog(@"bg lease to expire in <60s; refreshing location to renew it...");
                    [self startUpdatingLocation];
                }
                
            }
        }
        
    });
    
}

@end
