//
//  DIContainerTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Unit тесты для DI контейнера
//

import Testing
@testable import PixelFlow

struct DIContainerTests {
    private var container: DIContainer!

    init() {
        container = DIContainer()
    }

    @Test func testRegisterAndResolveService() {
        // Given
        let expectedService = MockService(name: "Test Service")

        // When
        container.register(expectedService, for: MockService.self)
        let resolvedService: MockService? = container.resolve(MockService.self)

        // Then
        #expect(resolvedService != nil)
        #expect(resolvedService?.name == expectedService.name)
    }

    @Test func testResolveNonExistentServiceReturnsNil() {
        // When
        let service: MockService? = container.resolve(MockService.self)

        // Then
        #expect(service == nil)
    }

    @Test func testRegisterWithNameAndResolve() {
        // Given
        let service1 = MockService(name: "Service 1")
        let service2 = MockService(name: "Service 2")

        // When
        container.register(service1, for: MockService.self, name: "first")
        container.register(service2, for: MockService.self, name: "second")

        let resolved1: MockService? = container.resolve(MockService.self, name: "first")
        let resolved2: MockService? = container.resolve(MockService.self, name: "second")

        // Then
        #expect(resolved1 != nil)
        #expect(resolved2 != nil)
        #expect(resolved1?.name == "Service 1")
        #expect(resolved2?.name == "Service 2")
    }

    @Test func testIsRegistered() {
        // Given
        let service = MockService(name: "Test")

        // When
        container.register(service, for: MockService.self)

        // Then
        #expect(container.isRegistered(MockService.self))
        #expect(!container.isRegistered(AnotherMockService.self))
    }

    @Test func testResetClearsAllServices() {
        // Given
        let service = MockService(name: "Test")
        container.register(service, for: MockService.self)

        // When
        container.reset()

        // Then
        #expect(!container.isRegistered(MockService.self))
    }

    @Test func testThreadSafety() async throws {
        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let service = MockService(name: "Service \(index)")
                    self.container.register(service, for: MockService.self, name: "service_\(index)")

                    let resolved: MockService? = self.container.resolve(MockService.self, name: "service_\(index)")
                    #expect(resolved != nil)
                    #expect(resolved?.name == "Service \(index)")
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func testGlobalFunctions() {
        // Given
        let service = MockService(name: "Global Test")

        // When
        register(service, for: MockService.self)
        let resolved: MockService? = resolve(MockService.self)

        // Then
        #expect(resolved != nil)
        #expect(resolved?.name == "Global Test")

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