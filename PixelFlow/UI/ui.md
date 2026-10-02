# App and presentation lifecycle

`AppDelegate` owns the lazy, app-scoped `AppCompositionRoot`. Each `SceneDelegate` obtains that root and asks it to create a `ParticleViewController` for the scene window.

`ParticleViewController` owns the render view and forwards user input and app lifecycle callbacks to `ParticleViewModel`. The view model loads the source image, creates one particle system for its render view, and cancels quality generation and cleans up the system when it is released.

Each `MTKView` receives a fresh particle-system graph. The renderer is installed as the view's weak delegate, and the controller keeps only a weak reference to the view. App-scoped services do not retain the view or its graph.

UIKit work is main-actor isolated. Image generation is asynchronous so it does not block presentation updates.
