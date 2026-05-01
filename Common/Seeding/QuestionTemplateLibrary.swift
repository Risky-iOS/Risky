import Foundation

/// Errors thrown by ``QuestionTemplateLibrary`` while loading the bundled question library.
public enum QuestionTemplateLibraryError: Error {
  /// The expected resource was not found in the bundle.
  case resourceNotFound(name: String)
}

/// Loader for the bundled set of default ``QuestionTemplate``s used to seed risk questions.
public enum QuestionTemplateLibrary {
  /// Loads the default question templates from the Common framework bundle.
  public static func loadBundled() throws -> [QuestionTemplate] {
    try load(from: RiskyCommonBundle.bundle)
  }

  /// Loads question templates from the given bundle. Used by tests with a custom bundle.
  public static func load(from bundle: Bundle) throws -> [QuestionTemplate] {
    guard let url = bundle.url(forResource: "DefaultQuestions", withExtension: "plist") else {
      throw QuestionTemplateLibraryError.resourceNotFound(name: "DefaultQuestions.plist")
    }
    let data = try Data(contentsOf: url)
    let file = try PropertyListDecoder().decode(QuestionTemplateFile.self, from: data)
    return file.questions
  }
}
