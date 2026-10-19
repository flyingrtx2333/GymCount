import Foundation

// Inspect the actual compiled app resources; no device installation or user data access.
@main
struct VerifyLocalization {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            fatalError("Usage: verify-localization <iPhone.app> <localization-extraction-directory>")
        }
        let phone = URL(fileURLWithPath: arguments[1])
        let watch = phone.appendingPathComponent("Watch/GymCount Watch App.app")
        let extraction = URL(fileURLWithPath: arguments[2])
        var keys: [String: Set<String>] = [:]
        let files = FileManager.default.enumerator(at: extraction, includingPropertiesForKeys: nil)!
        for case let file as URL in files where file.pathExtension == "stringsdata" {
            let data = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let target = (data["source"] as! String).contains("/GymCount Watch App/") ? "Watch" : "iPhone"
            let tables = data["tables"] as? [String: [[String: Any]]] ?? [:]
            for item in tables["Localizable"] ?? [] {
                let key = item["key"] as! String
                if key.range(of: "\\p{Han}", options: .regularExpression) != nil {
                    keys[target, default: []].insert(key)
                }
            }
        }
        precondition(!(keys["iPhone"] ?? []).isEmpty && !(keys["Watch"] ?? []).isEmpty,
                     "No compiler-extracted UI strings were found")
        var result: [String: Any] = [:]
        for (target, app) in [("iPhone", phone), ("Watch", watch)] {
            let bundle = Bundle(url: app)!
            let languages = bundle.localizations
            precondition(Set(languages).isSuperset(of: ["en", "zh-Hans"]))
            for (preference, expected) in [("en-US", "en"), ("zh-Hans-CN", "zh-Hans")] {
                precondition(Bundle.preferredLocalizations(from: languages, forPreferences: [preference]).first == expected)
            }
            for language in ["en", "zh-Hans"] {
                let resources = app.appendingPathComponent(language + ".lproj")
                let localized = Bundle(url: resources)!
                let table = try PropertyListSerialization.propertyList(
                    from: Data(contentsOf: resources.appendingPathComponent("Localizable.strings")),
                    format: nil) as! [String: String]
                let expectedName = language == "en" ? "PowerReps" : "健身计数器"
                precondition(localized.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist") == expectedName)
                for key in keys[target]! {
                    guard let translation = table[key] else { fatalError("Missing \(target)/\(language): \(key)") }
                    precondition(localized.localizedString(forKey: key, value: nil, table: nil) == translation)
                    precondition(placeholders(key) == placeholders(translation), "Format mismatch: \(key)")
                    if language == "en" { precondition(translation != key, "Untranslated: \(key)") }
                }
                var summary: [String: Any] = ["name": expectedName, "verifiedUIKeys": keys[target]!.count]
                if target == "iPhone" {
                    summary["startTraining"] = localized.localizedString(forKey: "开始训练", value: nil, table: nil)
                }
                result[target + "/" + language] = summary
            }
        }
        result["physicalDeviceUIValidated"] = false
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    static func placeholders(_ value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:\.\d+)?(?:lld|ld|d|f|@)"#)
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
            String(value[Range($0.range, in: value)!])
        }
    }
}
