//
//  ParticleAssembly.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import UIKit

class ParticleAssembly {
    // MARK: - Public Methods

    static func assemble() -> ViewController {
        let viewModel = ParticleViewModel()
        let viewController = ViewController(viewModel: viewModel)
        return viewController
    }
}
