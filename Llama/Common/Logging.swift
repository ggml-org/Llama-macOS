import Foundation

enum Logging {
  #if DEBUG
    static let subsystem = "app.llama.Llama.dev"
  #else
    static let subsystem = "app.llama.Llama"
  #endif
}
