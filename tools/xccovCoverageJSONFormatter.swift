#!/usr/bin/env swift

import Foundation

struct CoverageReport: Codable {

	let coveredLines: Int
	let coverage: Double
	let totalLines: Int
	let dateTimeStamp = Date().timeIntervalSince1970

	private enum CodingKeys: String, CodingKey {
		case coveredLines = "coveredLines"
		case coverage = "lineCoverage"
		case totalLines = "executableLines"
		case dateTimeStamp = "date"
	}
}

enum ScriptError: LocalizedError {
	case invalidArguments(arguments: [String])
	case cannotConvertSourceStringToData(string: String)
	case cannotConvertDestinationDataToString

	var errorDescription: String? {
		switch self {
		case .invalidArguments(var arguments):
			arguments.removeFirst()
			return "Invalid arguments. Got \(arguments). Expected only the absolute file path to json to format"
		case .cannotConvertSourceStringToData(let string):
			return "Cannot convert source JSON string to data. String: \(string)"
		case .cannotConvertDestinationDataToString:
			return "Cannot convert destination JSON data to UTF8 string"
		}
	}
}

let arguments = CommandLine.arguments
do {
	guard (arguments.count == 2) else {
		throw ScriptError.invalidArguments(arguments: arguments)
	}

	let filePath = CommandLine.arguments[1]
	
	let inJsonString = try String(contentsOfFile: filePath, encoding: .utf8)
	guard let inJsonData = inJsonString.data(using: .utf8) else {
		throw ScriptError.cannotConvertSourceStringToData(string: inJsonString)
	}

	let coverageReport = try JSONDecoder().decode(CoverageReport.self, from: inJsonData)
	let outJsonData = try JSONEncoder().encode(coverageReport)
	guard let outJsonString = String(data: outJsonData, encoding: .utf8) else {
		throw ScriptError.cannotConvertDestinationDataToString
	}

	print(outJsonString)
} catch {
	print((error as? LocalizedError)?.errorDescription ?? error)
	exit(1)
}
