//
//  InputTypeOptions+CoreDataProperties.swift
//  NowFloats-iOSSDK
//
//  Created by Rakesh Tatekonda on 17/10/17.
//  Copyright © 2017 NowFloats. All rights reserved.
//
//

import Foundation
import CoreData


extension InputTypeOptions {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<InputTypeOptions> {
        return NSFetchRequest<InputTypeOptions>(entityName: "InputTypeOptions")
    }

    @NSManaged public var multiple: Int16
    @NSManaged public var options: NSSet?

}

// MARK: Generated accessors for options
extension InputTypeOptions {

    @objc(addOptionsObject:)
    @NSManaged public func addToOptions(_ value: Options)

    @objc(removeOptionsObject:)
    @NSManaged public func removeFromOptions(_ value: Options)

    @objc(addOptions:)
    @NSManaged public func addToOptions(_ values: NSSet)

    @objc(removeOptions:)
    @NSManaged public func removeFromOptions(_ values: NSSet)

}
