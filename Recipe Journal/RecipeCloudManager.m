//
//  RecipeCloudManager.m
//  Recipe Journal
//
//  Created by Robert Miller on 2/7/15.
//  Copyright (c) 2015 Robert Miller. All rights reserved.
//

#import "RecipeCloudManager.h"
#include "Ingredient.h"
#include "AppDelegate.h"
#include "RecipeJournalHelper.h"

@implementation RecipeCloudManager

-(instancetype)init {
    self = [super init];

    if (self) {
        _container = [CKContainer defaultContainer];
        _privateDatabase = [_container privateCloudDatabase];
        _pubicDatabase = [_container publicCloudDatabase];
    }
    
    return self;
}

bool status = false;
bool notCompleted = true;
-(BOOL)isLoggedIn {
    
    [_container accountStatusWithCompletionHandler:^(CKAccountStatus accountStatus, NSError *error) {
        if (error) {
            NSLog(@"error logging in with error: %@", error);
            status = false;
        }
        else {
            if (accountStatus == CKAccountStatusAvailable) {
                status = true;
            }
            else {
                status = false;
            }
        }
        notCompleted = false;
    }];
    while (notCompleted) {
        //don't return status until status is fetched
    }
    return status;
}

#pragma mark - Recipe Sync Methods

-(void)modifyRecipeToCloud:(Event*)sender {
    [_privateDatabase fetchRecordWithID:[[CKRecordID alloc] initWithRecordName:[sender recordID]] completionHandler:^(CKRecord *record, NSError *error) {
        
        [record setValue:[NSNumber numberWithBool:true] forKey:@"Favorited"];
        
        CKModifyRecordsOperation *saveRecords = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:@[record] recordIDsToDelete:@[]];
        [saveRecords setSavePolicy:CKRecordSaveAllKeys];
        saveRecords.modifyRecordsCompletionBlock = ^(NSArray *savedRecords, NSArray *deletedRecordIDs, NSError *error) {
            
            if (error) {
                NSLog(@"[%@] Error pushing local data: %@", self.class, error);
            }
            
        };
        
        [_privateDatabase addOperation:saveRecords];
    }];
}

-(void)saveRecipeToCloud:(Event*)sender {
    
    CKRecord *newRecord = [[CKRecord alloc] initWithRecordType:@"Recipe"];
    
    [newRecord setValue:[sender cookTimeMinutes] forKey:@"CookTimeMinutes"];
    [newRecord setValue:[sender cookingProcess] forKey:@"CookingProcess"];
    [newRecord setValue:[sender difficulty] forKey:@"Difficulty"];
    [newRecord setValue:[sender notes] forKey:@"Notes"];
    [newRecord setValue:[sender prepTimeMinutes] forKey:@"PrepTimeMinutes"];
    [newRecord setValue:[sender returnPrepartionStepsArray] forKey:@"Preparation"];
    [newRecord setValue:[sender rating] forKey:@"Rating"];
    [newRecord setValue:[sender recipeName] forKey:@"RecipeName"];
    [newRecord setValue:[sender servingSize] forKey:@"ServingSize"];
    [newRecord setValue:[sender winePairing] forKey:@"WinePairing"];
    //[newRecord setValue:[sender recipeIconImage] forKey:@"RecipeIconImage"];
    //[newRecord setValue:[sender ingredients] forKey:@"IngredientsList"];
    
    CKAsset *photoAsset = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:[sender imageURL]]];
    [newRecord setValue:photoAsset forKey:@"RecipeIconImage"];
    
    [_privateDatabase saveRecord:newRecord completionHandler:^(CKRecord *record, NSError *error) {
        if (error) {
            NSLog(@"error: %@ with record: %@", error, [record description]);
        }
        else {
            NSLog(@"Hooray!");
            //[sender setRecordID:[record recordID]];
            if (sender) {
                [sender setRecordID:[[record recordID] recordName]];
                
                NSManagedObjectContext *context = [[AppDelegate sharedInstance] managedObjectContext];
                
                if (![context save:&error]) {
                    // Replace this implementation with code to handle the error appropriately.
                    // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                    NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
                    abort();
                }
            }
        }
    }];
}

-(void)removeRecipeFromCloud:(Event*)sender complete:(void (^)(NSError *))completionHandler {
    CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:[sender recordID]];
    [_privateDatabase deleteRecordWithID:recordID completionHandler:^(CKRecordID *recordID, NSError *error) {
        if (error) {
            NSLog(@"error: %@ with record: %@", error, [recordID description]);
        }
        else {
            NSLog(@"Hooray! Deleted!");
        }
        completionHandler(error);
    }];
}

BOOL refresh = false;
-(void)fetchRecords:(void (^)(NSError*error, bool refresh))completionHandler {
    
    NSPredicate *predicate = [NSPredicate predicateWithValue:true];
    CKQuery *query = [[CKQuery alloc] initWithRecordType:@"Recipe" predicate:predicate];
    
    refresh = false;
    [_privateDatabase performQuery:query inZoneWithID:nil completionHandler:^(NSArray *results, NSError *error) {
        if (error) {
            NSLog(@"error: %@", error);
        }
        else {
            NSManagedObjectContext *dataCenter = [[AppDelegate sharedInstance] managedObjectContext];
            NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Event"];
            
            NSError *error = nil;
            NSArray *coreDataArray = [dataCenter executeFetchRequest:fetchRequest error:&error];
            
            BOOL isSynced = false;
            for (CKRecord *record in results) {
                for (Event *event in coreDataArray) {
                    if ([[[record recordID] recordName] isEqualToString:[event recordID]]) {
                        isSynced = true;
                        break;
                    }
                }
                if (isSynced) {
                    //This record already exists
                    isSynced = false;
                }
                else {
                    refresh = true;
                    
                    NSManagedObjectContext *context = [[AppDelegate sharedInstance] managedObjectContext];
                    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Event" inManagedObjectContext:context];
                    
                    //NSManagedObjectContext *context = [self.fetchedResultsController managedObjectContext];
                    NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:[entity name] inManagedObjectContext:context];
                    
                    Event *newEvent = (Event*)newManagedObject;
                    [newEvent setEventWithRecord:record];
                    
                    if (![context save:&error]) {
                        // Replace this implementation with code to handle the error appropriately.
                        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
                        abort();
                    }
                }
            }
        }
        completionHandler(error, refresh);
    }];
}

-(void)fetchRecordsWithSource:(NSString *)source completionBlock:(void (^)(NSError *, BOOL))completionHandler {
    
    if ([source isEqualToString:RECIPELISTSOURCE]) {
        [self fetchRecords:^(NSError *error, bool refresh) {
            completionHandler(error, refresh);
        }];
    }
    
}

#pragma mark - Grocery List Sync Methods
-(void)saveListToItem:(GroceryList *)list {
    
    CKRecord *record = [[CKRecord alloc] initWithRecordType:@"Items"];
    
    [record setValue:[list name] forKey:@"name"];
    [record setValue:[list amount] forKey:@"amount"];
    [record setValue:[list type] forKey:@"size"];
    
    [_privateDatabase saveRecord:record completionHandler:^(CKRecord *record, NSError *error) {
        if (error) {
            NSLog(@"error saving record: %@ with error: %@", [record description], error);
        }
        else {
            NSLog(@"woot!");
            [list setRecordID:[[record recordID] recordName]];
            
            NSManagedObjectContext *context = [[AppDelegate sharedInstance] managedObjectContext];
            
            if (![context save:&error]) {
                // Replace this implementation with code to handle the error appropriately.
                // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
                abort();
            }
        }
    }];
    
}

-(void)removeItemFromCloud:(GroceryList *)list {
    
    
    
}

@end
