import Foundation

// Run: swift Scripts/LocalizationCheck.swift <ColdHot.app>
let appURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
guard let bundle = Bundle(url: appURL) else { fatalError("App bundle not found") }
let languages = ["en", "zh-Hans"]
var tables: [String: [String: String]] = [:]
for language in languages {
    guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
          let data = FileManager.default.contents(atPath: path),
          let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
        fatalError("Missing \(language) localization")
    }
    tables[language] = table
}
let english = tables["en"]!
let chinese = tables["zh-Hans"]!
precondition(!english.isEmpty, "Translation table is empty")
precondition(Set(english.keys) == Set(chinese.keys), "Language keys differ")
let placeholders = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|d|@|(?:\.\d+)?f)"#)
func arguments(_ text: String) -> [String] {
    placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
        String(text[Range($0.range, in: text)!])
    }.sorted()
}
for (key, value) in english {
    precondition(!value.isEmpty, "Empty English translation: \(key)")
    precondition(value.range(of: #"\p{Han}"#, options: .regularExpression) == nil, "Untranslated English: \(key)")
    precondition(arguments(value) == arguments(chinese[key]!), "Format arguments differ: \(key)")
}
precondition(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["en-US"]).first == "en")
precondition(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["zh-Hans-CN"]).first == "zh-Hans")
for (language, expected) in [("en", "Memory"), ("zh-Hans", "内存")] {
    let localizedBundle = Bundle(path: bundle.path(forResource: language, ofType: "lproj")!)!
    precondition(localizedBundle.localizedString(forKey: "内存", value: nil, table: nil) == expected)
}
print("Localization checks passed: \(english.count) messages in English and Simplified Chinese")
