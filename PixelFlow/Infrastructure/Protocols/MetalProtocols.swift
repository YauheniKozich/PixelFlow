//
//  MetalProtocols.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Протоколы для Metal компонентов
//

import Metal
import MetalKit

/// Протокол для Metal устройства
protocol MetalDeviceProtocol {
    /// Создает буфер с данными
    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer?

    /// Создает буфер с байтами
    func makeBuffer(bytes pointer: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> MTLBuffer?

    /// Создает библиотеку по умолчанию
    func makeDefaultLibrary() -> MTLLibrary?

    /// Создает библиотеку из файла
    func makeLibrary(filepath: String) throws -> MTLLibrary

    /// Создает очередь команд
    func makeCommandQueue() -> MTLCommandQueue?

    /// Создает compute pipeline state
    func makeComputePipelineState(function: MTLFunction) throws -> MTLComputePipelineState

    /// Создает render pipeline state
    func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState

    /// Создает sampler state
    func makeSamplerState(descriptor: MTLSamplerDescriptor) -> MTLSamplerState?

    /// Создает depth stencil state
    func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> MTLDepthStencilState?

    /// Поддерживает ли устройство семейство
    func supportsFamily(_ family: MTLGPUFamily) -> Bool

    /// Имя устройства
    var name: String { get }

    /// Поддерживаемые возможности
    var readWriteTextureSupport: MTLReadWriteTextureTier { get }

    /// Максимальный размер буфера
    var maxBufferLength: Int { get }
}

/// Протокол для Metal буфера
protocol MetalBufferProtocol {
    /// Указатель на содержимое буфера
    func contents() -> UnsafeMutableRawPointer

    /// Длина буфера
    var length: Int { get }

    /// Режим хранения
    var storageMode: MTLStorageMode { get }

    /// Устройство
    var device: MTLDevice { get }

    /// Метка для отладки
    var label: String? { get set }

    /// CPU кэш режим
    var cpuCacheMode: MTLCPUCacheMode { get }
}

/// Протокол для Metal текстуры
protocol MetalTextureProtocol {
    /// Ширина текстуры
    var width: Int { get }

    /// Высота текстуры
    var height: Int { get }

    /// Формат пикселей
    var pixelFormat: MTLPixelFormat { get }

    /// Тип текстуры
    var textureType: MTLTextureType { get }

    /// Уровень детализации
    var mipmapLevelCount: Int { get }

    /// Количество семплов
    var sampleCount: Int { get }

    /// Использование текстуры
    var usage: MTLTextureUsage { get }

    /// Доступность для шейдеров
    var isShaderReadable: Bool { get }

    /// Доступность для записи
    var isShaderWriteable: Bool { get }

    /// Заменяет регион текстуры
    func replace(region: MTLRegion, mipmapLevel: Int, withBytes: UnsafeRawPointer, bytesPerRow: Int)

    /// Получает байты из региона
    func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow: Int, from region: MTLRegion, mipmapLevel: Int)
}

/// Протокол для Metal очереди команд
protocol MetalCommandQueueProtocol {
    /// Создает буфер команд
    func makeCommandBuffer() -> MTLCommandBuffer?

    /// Метка для отладки
    var label: String? { get set }

    /// Устройство
    var device: MTLDevice { get }
}

/// Протокол для Metal буфера команд
protocol MetalCommandBufferProtocol {
    /// Создает энкодер compute команд
    func makeComputeCommandEncoder() -> MTLComputeCommandEncoder?

    /// Создает энкодер render команд
    func makeRenderCommandEncoder(descriptor: MTLRenderPassDescriptor) -> MTLRenderCommandEncoder?

    /// Создает энкодер blit команд
    func makeBlitCommandEncoder() -> MTLBlitCommandEncoder?

    /// Добавляет завершенный хендлер
    func addCompletedHandler(_ handler: @escaping MTLCommandBufferHandler)

    /// Добавляет запланированный хендлер
    func addScheduledHandler(_ handler: @escaping MTLCommandBufferHandler)

    /// Ожидает завершения
    func waitUntilCompleted()

    /// Коммитит буфер команд
    func commit()

    /// Статус буфера команд
    var status: MTLCommandBufferStatus { get }

    /// Ошибка выполнения
    var error: Error? { get }

    /// Метка для отладки
    var label: String? { get set }
}

/// Протокол для Metal compute command encoder
protocol MetalComputeCommandEncoderProtocol {
    /// Устанавливает compute pipeline state
    func setComputePipelineState(_ state: MTLComputePipelineState)

    /// Устанавливает буфер
    func setBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int)

    /// Устанавливает текстуру
    func setTexture(_ texture: MTLTexture?, index: Int)

    /// Устанавливает sampler state
    func setSamplerState(_ sampler: MTLSamplerState?, index: Int)

    /// Устанавливает константы
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)

    /// Отправляет потоки
    func dispatchThreadgroups(_ threadgroupsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize)

    /// Отправляет потоки с непрямыми размерами
    func dispatchThreads(_ threadsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize)

    /// Завершает энкодинг
    func endEncoding()

    /// Метка для отладки
    var label: String? { get set }
}

/// Протокол для Metal render command encoder
protocol MetalRenderCommandEncoderProtocol {
    /// Устанавливает render pipeline state
    func setRenderPipelineState(_ pipelineState: MTLRenderPipelineState)

    /// Устанавливает vertex буфер
    func setVertexBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int)

    /// Устанавливает fragment буфер
    func setFragmentBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int)

    /// Устанавливает vertex текстуру
    func setVertexTexture(_ texture: MTLTexture?, index: Int)

    /// Устанавливает fragment текстуру
    func setFragmentTexture(_ texture: MTLTexture?, index: Int)

    /// Устанавливает viewport
    func setViewport(_ viewport: MTLViewport)

    /// Устанавливает scissor rect
    func setScissorRect(_ rect: MTLScissorRect)

    /// Рисует примитивы
    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int)

    /// Рисует индексированные примитивы
    func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: MTLBuffer, indexBufferOffset: Int)

    /// Завершает энкодинг
    func endEncoding()

    /// Метка для отладки
    var label: String? { get set }
}

/// Протокол для Metal view
protocol MetalViewProtocol: MTKView {
    /// Устройство Metal
    var device: MTLDevice? { get set }

    /// Делегат view
    var delegate: MTKViewDelegate? { get set }

    /// Формат цвета
    var colorPixelFormat: MTLPixelFormat { get set }

    /// Формат глубины
    var depthStencilPixelFormat: MTLPixelFormat { get set }

    /// Формат stencil
    var stencilAttachmentPixelFormat: MTLPixelFormat { get set }

    /// Количество семплов для multisampling
    var sampleCount: Int { get set }

    /// Размер view
    var drawableSize: CGSize { get set }

    /// Только framebuffer
    var framebufferOnly: Bool { get set }

    /// Предпочитаемая частота кадров
    var preferredFramesPerSecond: Int { get set }

    /// Пауза
    var isPaused: Bool { get set }

    /// Включить setNeedsDisplay
    var enableSetNeedsDisplay: Bool { get set }

    /// Текущий drawable
    var currentDrawable: CAMetalDrawable? { get }

    /// Текущий render pass descriptor
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }

    /// Depth stencil текстура
    var depthStencilTexture: MTLTexture? { get }

    /// Multisample color текстура
    var multisampleColorTexture: MTLTexture? { get }
}
