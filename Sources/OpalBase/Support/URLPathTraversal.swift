// URLPathTraversal.swift

import Foundation

enum URLPathTraversal {
    static func containsPathTraversal(_ pathComponents: [String]) -> Bool {
        pathComponents.contains(where: isPathTraversalComponent)
    }

    static func containsPathTraversal(inPath path: String) -> Bool {
        containsPathTraversal(path.split(separator: "/").map(String.init))
    }

    static func containsPathTraversal(in resourceLocation: URL) -> Bool {
        containsPathTraversal(inPath: resourceLocation.path)
    }

    static func containsPathTraversal(inLocationValue locationValue: String) -> Bool {
        guard let components = URLComponents(string: locationValue) else { return false }
        return containsPathTraversal(inPath: components.path)
    }

    static func isPathTraversalComponent(_ pathComponent: String) -> Bool {
        var currentPathComponent = pathComponent
        while true {
            guard !currentPathComponent.contains("\\") else { return true }
            if currentPathComponent == "." || currentPathComponent == ".." {
                return true
            }
            guard let decodedPathComponent = currentPathComponent.removingPercentEncoding,
                  decodedPathComponent != currentPathComponent else {
                return false
            }
            guard !decodedPathComponent.contains("/") else {
                return true
            }
            currentPathComponent = decodedPathComponent
        }
    }
}
