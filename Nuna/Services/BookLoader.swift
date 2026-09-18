//
//  BookLoader.swift
//  Nuna
//
//  Carrega os livros do bundle. O JSON é o mesmo formato que o pipeline
//  (scripts-picturebook) produz na etapa 1.
//

import Foundation

enum BookLoaderError: LocalizedError {
    case notFound(String)
    case decoding(String, Error)

    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Couldn't find \(name).json in the bundle."
        case .decoding(let name, let err):
            return "Failed to read \(name).json: \(err.localizedDescription)"
        }
    }
}

enum BookLoader {

    static func load(_ name: String, bundle: Bundle = .main) throws -> Book {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw BookLoaderError.notFound(name)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Book.self, from: data)
        } catch {
            throw BookLoaderError.decoding(name, error)
        }
    }

    /// Todos os livros presentes no bundle, ordenados pelo título resolvido.
    static func loadAll(bundle: Bundle = .main) -> [Book] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return urls
            .compactMap { try? JSONDecoder().decode(Book.self, from: Data(contentsOf: $0)) }
            .sorted { $0.title.resolved() < $1.title.resolved() }
    }
}
