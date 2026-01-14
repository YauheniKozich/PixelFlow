//
//  DIContainerTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Unit тесты для DI контейнера
//

import XCTest
@testable import PixelFlow

final class DIContainerTests: XCTestCase {
    private var container: DIContainer!

    override func setUp() {
        super.setUp()
        container = DIContainer()
    }

    override func tearDown() {
        container.reset()
        container = nil
        super.tearDown()
    }

    func testRegisterAndResolveService() {
        // Given
        let expectedService = MockService(name: "Test Service")

        // When
        container.register(expectedService, for: MockService.self)
        let resolvedService: MockService? = container.resolve(MockService.self)

        // Then
        XCTAssertNotNil(resolvedService)
        XCTAssertEqual(resolvedService?.name, expectedService.name)
    }

    func testResolveNonExistentServiceReturnsNil() {
        // When
        let service: MockService? = container.resolve(MockService.self)

        // Then
        XCTAssertNil(service)
    }

    func testRegisterWithNameAndResolve() {
        // Given
        let service1 = MockService(name: "Service 1")
        let service2 = MockService(name: "Service 2")

        // When
        container.register(service1, for: MockService.self, name: "first")
        container.register(service2, for: MockService.self, name: "second")

        let resolved1: MockService? = container.resolve(MockService.self, name: "first")
        let resolved2: MockService? = container.resolve(MockService.self, name: "second")

        // Then
        XCTAssertNotNil(resolved1)
        XCTAssertNotNil(resolved2)
        XCTAssertEqual(resolved1?.name, "Service 1")
        XCTAssertEqual(resolved2?.name, "Service 2")
    }

    func testIsRegistered() {
        // Given
        let service = MockService(name: "Test")

        // When
        container.register(service, for: MockService.self)

        // Then
        XCTAssertTrue(container.isRegistered(MockService.self))
        XCTAssertFalse(container.isRegistered(AnotherMockService.self))
    }

    func testResetClearsAllServices() {
        // Given
        let service = MockService(name: "Test")
        container.register(service, for: MockService.self)

        // When
        container.reset()

        // Then
        XCTAssertFalse(container.isRegistered(MockService.self))
    }

    func testThreadSafety() {
        // Given
        let expectation = self.expectation(description: "All operations completed")
        expectation.expectedFulfillmentCount = 100

        // When
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let service = MockService(name: "Service \(index)")
            container.register(service, for: MockService.self, name: "service_\(index)")

            let resolved: MockService? = container.resolve(MockService.self, name: "service_\(index)")
            XCTAssertNotNil(resolved)
            XCTAssertEqual(resolved?.name, "Service \(index)")

            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testGlobalFunctions() {
        // Given
        let service = MockService(name: "Global Test")

        // When
        register(service, for: MockService.self)
        let resolved: MockService? = resolve(MockService.self)

        // Then
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.name, "Global Test")

        // Cleanup
        AppContainer.shared.reset()
    }
}

// MARK: - Mock Objects

private struct MockService {
    let name: String
}

private struct AnotherMockService {
    let id: Int
}