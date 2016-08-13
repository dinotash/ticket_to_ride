//
//  Duplet.swift
//  Ticket To Ride
//
//  Created by Tom Curtis on 6 Aug 2016.
//  Copyright © 2016 Tom Curtis. All rights reserved.
//

//Lets us pair two keys in a dictionary for use in caching during imports
//http://stackoverflow.com/questions/31168757/swift-creating-a-hashable-tuple-like-struct

import Foundation

struct Duplet<A: Hashable, B: Hashable>: Hashable {
    let one: A
    let two: B
    
    var hashValue: Int {
        return one.hashValue ^ two.hashValue
    }
    
    init(_ one: A, _ two: B) {
        self.one = one
        self.two = two
    }
}

func ==<A, B> (lhs: Duplet<A, B>, rhs: Duplet<A, B>) -> Bool {
    return lhs.one == rhs.one && lhs.two == rhs.two
}