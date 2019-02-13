//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//

import Foundation
import XCTest
@testable import Swift Distributed ActorsActor
import NIO
import NIOFoundationCompat
import SwiftDistributedActorsActorTestKit

class SerializationTests: XCTestCase {

    let system = ActorSystem("SerializationTests") { settings in
        settings.serialization.registerCodable(for: ActorRef<String>.self, underId: 1001)
        settings.serialization.registerCodable(for: HasStringRef.self, underId: 1002)
    }
    lazy var testKit = ActorTestKit(system)

    override func tearDown() {
        system.terminate()
    }

    func test_sanity_roundTripBetweenFoundationDataAndNioByteBuffer() throws {
        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 5)
        buf.write(string: "hello")

        let data: Data = buf.getData(at: 0, length: buf.readableBytes)!

        let out: ByteBuffer = data.withUnsafeBytes { bytes in
            var out = allocator.buffer(capacity: data.count)
            out.write(bytes: bytes)
            return out
        }

        buf.shouldEqual(out)
    }

    // MARK: Codable round-trip tests for of simple Swift Distributed Actors types

    func test_serialize_actorPath() throws {
        let path = try ActorPath(root: "user") / ActorPathSegment("hello")
        let encoded = try JSONEncoder().encode(path)
        pinfo("Serialized actor path: \(encoded.copyToNewByteBuffer().stringDebugDescription())")

        let pathAgain = try JSONDecoder().decode(ActorPath.self, from: encoded)
        pinfo("Deserialized again: \(String(reflecting: pathAgain))")

        pathAgain.shouldEqual(path)
    }

    func test_serialize_uniqueActorPath() throws {
        let path: UniqueActorPath = (try ActorPath(root: "user") / ActorPathSegment("hello")).makeUnique(uid: .random())
        let encoded = try JSONEncoder().encode(path)
        pinfo("Serialized actor path: \(encoded.copyToNewByteBuffer().stringDebugDescription())")

        let pathAgain = try JSONDecoder().decode(UniqueActorPath.self, from: encoded)
        pinfo("Deserialized again: \(String(reflecting: pathAgain))")

        pathAgain.shouldEqual(path)
    }

    // MARK: Actor ref serialization and resolve

    func test_serialize_actorRef_inMessage() throws {
        let ref: ActorRef<String> = try system.spawn(.ignore, name: "hello")
        let hasRef = HasStringRef(containedRef: ref)

        pinfo("Before serialize: \(hasRef)")

        let bytes = try shouldNotThrow {
            return try system.serialization.serialize(message: hasRef)
        }
        pinfo("serialized ref: \(bytes.stringDebugDescription())")

        let back: HasStringRef = try shouldNotThrow {
            return try system.serialization.deserialize(to: HasStringRef.self, bytes: bytes)
        }
        pinfo("Deserialized again: \(back)")

        back.shouldEqual(hasRef)
    }

    // FIXME: Implement deserializing into deadLetters: https://github.com/apple/swift-distributed-actors/issues/321
//    func test_deserialize_alreadyDeadActorRef_shouldDeserializeAsDeadLetters() throws {
//        let stoppedRef: ActorRef<String> = try system.spawn(.stopped, name: "dead-on-arrival") // stopped
//        let hasRef = HasStringRef(containedRef: stoppedRef)
//
//        pinfo("Before serialize: \(hasRef)")
//
//        let bytes = try shouldNotThrow {
//            return try system.serialization.serialize(message: hasRef)
//        }
//        pinfo("serialized ref: \(bytes.stringDebugDescription())")
//
//        let back: HasStringRef = try shouldNotThrow {
//            return try system.serialization.deserialize(to: HasStringRef.self, bytes: bytes)
//        }
//        pinfo("Deserialized again: \(back)")
//
//        back.containedRef.tell("Hello") // SHOULD be a dead letter
//    }

    func test_serialize_shouldNotSerializeNotRegisteredType() throws {
        let err = shouldThrow {
            return try system.serialization.serialize(message: NotCodableHasInt(containedInt: 1337))
        }

        switch err {
        case SerializationError<NotCodableHasInt>.noSerializerRegisteredFor:
            () // good
        default:
            fatalError("Not expected error type! Was: \(err):\(type(of: err))")
        }
    }

    // MARK: Serialized messages in actor communication, locally

    func test_serializeMessages_plainStringMessages() throws {
        let system = ActorSystem("SerializeMessages") { settings in
            settings.serialization.allMessages = true
        }

        let p = testKit.spawnTestProbe(name: "p1", expecting: String.self)
        let echo: ActorRef<String> = try system.spawn(.receiveMessage { msg in
            p.ref.tell("echo:\(msg)")
            return .same
        }, name: "echo")

        echo.tell("hi!")
        try p.expectMessage("echo:hi!")
    }

}

// MARK: Example types for serialization tests

protocol Top: Hashable, Codable {
    var path: ActorPath { get }
}

class Mid: Top, Hashable {
    let _path: ActorPath

    init() {
        self._path = try! ActorPath(root: "hello")
    }

    var path: ActorPath {
        return _path
    }

    func hash(into hasher: inout Hasher) {
        _path.hash(into: &hasher)
    }

    static func ==(lhs: Mid, rhs: Mid) -> Bool {
        return lhs.path == rhs.path
    }
}

struct HasStringRef: Codable, Equatable {
    let containedRef: ActorRef<String>
}

struct HasIntRef: Codable, Equatable {
    let containedRef: ActorRef<Int>
}

struct NotCodableHasInt: Equatable {
    let containedInt: Int
}

struct NotCodableHasIntRef: Equatable {
    let containedRef: ActorRef<Int>
}
