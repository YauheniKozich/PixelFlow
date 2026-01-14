//
//  ParticleSystemProtocols.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Протоколы для компонентов ParticleSystem
//

import MetalKit
import CoreGraphics

/// Протокол для координатора системы частиц
protocol ParticleSystemCoordinatorProtocol: AnyObject {
    /// Начинает симуляцию частиц
    func startSimulation()

    /// Останавливает симуляцию частиц
    func stopSimulation()

    /// Переключает состояние симуляции
    func toggleSimulation()

    /// Запускает специальный эффект "молниеносная буря"
    func startLightningStorm()

    /// Обновляет конфигурацию системы частиц
    func updateConfiguration(_ config: ParticleGenerationConfig)

    /// Устанавливает размер экрана
    func configure(screenSize: CGSize)

    /// Выполняет замену частиц на высококачественные асинхронно
    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void)

    /// Инициализирует систему с быстрой превью
    func initializeFastPreview()

    /// Очищает все ресурсы
    func cleanup()

    /// Возвращает текущее состояние симуляции
    var hasActiveSimulation: Bool { get }

    /// Возвращает true если используются высококачественные частицы
    var isHighQuality: Bool { get }

    /// Возвращает количество частиц
    var particleCount: Int { get }

    /// Возвращает источник изображения
    var sourceImage: CGImage? { get }

    /// Возвращает буфер частиц для рендерера
    var particleBuffer: MTLBuffer? { get }
}

/// Протокол для рендерера Metal
protocol MetalRendererProtocol: AnyObject, MTKViewDelegate {
    /// Настраивает Metal pipelines
    func setupPipelines() throws

    /// Настраивает буферы
    func setupBuffers(particleCount: Int) throws

    /// Обновляет параметры симуляции
    func updateSimulationParams()

    /// Сбрасывает счетчик собранных частиц
    func resetCollectedCounter()

    /// Проверяет завершение сбора частиц
    func checkCollectionCompletion()

    /// Очищает Metal ресурсы
    func cleanup()

    /// Устанавливает буфер частиц извне
    func setParticleBuffer(_ buffer: MTLBuffer?)

    /// Устройство Metal
    var device: MTLDevice { get }

    /// Очередь команд Metal
    var commandQueue: MTLCommandQueue { get }

    /// Render pipeline state
    var renderPipeline: MTLRenderPipelineState? { get }

    /// Compute pipeline state
    var computePipeline: MTLComputePipelineState? { get }

    /// Буфер частиц
    var particleBuffer: MTLBuffer? { get }

    /// Буфер параметров
    var paramsBuffer: MTLBuffer? { get }

    /// Буфер счетчика собранных частиц
    var collectedCounterBuffer: MTLBuffer? { get }
}

/// Протокол для движка симуляции
protocol SimulationEngineProtocol: AnyObject {
    /// Запускает симуляцию
    func start()

    /// Останавливает симуляцию
    func stop()

    /// Запускает сбор частиц
    func startCollecting()

    /// Запускает молниеносную бурю
    func startLightningStorm()

    /// Обновляет прогресс сбора
    func updateProgress(_ progress: Float)

    /// Текущее состояние симуляции
    var state: SimulationState { get }

    /// Активна ли симуляция
    var isActive: Bool { get }

    /// Колбек для сброса счетчика
    var resetCounterCallback: (() -> Void)? { get set }
}

/// Протокол для менеджера состояний
protocol StateManagerProtocol: AnyObject {
    /// Текущее состояние
    var currentState: SimulationState { get }

    /// Переходит в новое состояние
    func transition(to state: SimulationState)

    /// Активно ли текущее состояние
    var isActive: Bool { get }
}

/// Протокол для физического движка
protocol PhysicsEngineProtocol: AnyObject {
    /// Обновляет физику частиц
    func update(deltaTime: Float)

    /// Применяет силы к частицам
    func applyForces()

    /// Сбрасывает физику
    func reset()
}

/// Протокол для хранилища частиц
protocol ParticleStorageProtocol: AnyObject {
    /// Буфер частиц
    var particleBuffer: MTLBuffer? { get }

    /// Количество частиц
    var particleCount: Int { get }

    /// Инициализирует хранилище с количеством частиц
    func initialize(with particleCount: Int)

    /// Создает частицы для превью
    func createFastPreviewParticles()

    /// Заменяет частицы на высококачественные
    func recreateHighQualityParticles()

    /// Очищает хранилище
    func clear()
}

/// Протокол для генератора частиц
protocol ParticleGeneratorProtocol: AnyObject {
    /// Генерирует частицы из изображения
    func generateParticles(from image: CGImage, config: ParticleGenerationConfig) throws -> [Particle]

    /// Обновляет размер экрана
    func updateScreenSize(_ size: CGSize)

    /// Очищает кэш
    func clearCache()

    /// Исходное изображение
    var image: CGImage? { get }
}

/// Протокол для загрузчика изображений
protocol ImageLoaderProtocol {
    /// Загружает изображение по имени
    func loadImage(named name: String) -> CGImage?

    /// Загружает изображение из URL
    func loadImage(from url: URL) async throws -> CGImage

    /// Создает тестовое изображение
    func createTestImage() -> CGImage?

    /// Загружает изображение с fallback к тестовому изображению
    func loadImageWithFallback() -> CGImage?
}

/// Протокол для конфигурационного менеджера
protocol ConfigurationManagerProtocol {
    /// Текущая конфигурация
    var currentConfig: ParticleGenerationConfig { get set }

    /// Применяет новую конфигурацию
    func apply(_ config: ParticleGenerationConfig)

    /// Возвращает оптимальное количество частиц для изображения
    func optimalParticleCount(for image: CGImage, preset: QualityPreset) -> Int

    /// Сбрасывает к стандартной конфигурации
    func resetToDefaults()
}

/// Протокол для службы логирования
protocol LoggerProtocol {
    /// Логирует информационное сообщение
    func info(_ message: String)

    /// Логирует предупреждение
    func warning(_ message: String)

    /// Логирует ошибку
    func error(_ message: String)

    /// Логирует отладочное сообщение
    func debug(_ message: String)
}

/// Протокол для менеджера памяти
protocol MemoryManagerProtocol: AnyObject {
    /// Отслеживает использование памяти
    func trackMemoryUsage(_ bytes: Int64)

    /// Освобождает память
    func releaseMemory()

    /// Обрабатывает уведомление о низкой памяти
    func handleLowMemory()

    /// Текущее использование памяти
    var currentUsage: Int64 { get }
}