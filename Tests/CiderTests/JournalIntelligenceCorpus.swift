import Foundation
@testable import Cider

enum JournalIntelligenceCorpus {
    struct Capture: Equatable {
        var id: String
        var time: String
        var source: String
        var surface: String
        var text: String
    }

    static let date = "2026-07-12"

    static let captures: [Capture] = [
        Capture(
            id: "capture-text-morning",
            time: "08:10",
            source: "cider-cli text",
            surface: "cli",
            text: """
            Maya started a new job at Alder Labs. I went to Discovery Park. I loved the cedar loop hike. I promised Maya I would bring the trail map tomorrow. Remember to email the signed permit. I watched Arrival last night. Remember that hiking before work improves my mood.
            """
        ),
        Capture(
            id: "capture-voice-midday",
            time: "12:30",
            source: "voice transcript",
            surface: "voice",
            text: """
            We are planning a September trip to Kyoto. Save the ferry itinerary PDF with the trip. I went to Discovery Park again. Maybe Alex mentioned the old mall, but I am not sure.
            """
        ),
        Capture(
            id: "capture-voice-correction",
            time: "18:45",
            source: "voice transcript",
            surface: "voice",
            text: """
            I went to Portland. Correction: I did not go to Portland; I went to Seattle. I liked it. I did not visit the Red Barn.
            """
        ),
    ]

    static var journalMarkdown: String {
        (["# Daily Journal \(date)"] + captures.map { capture in
            JournalTitle.appendSection(time: capture.time, source: capture.source, body: capture.text)
        }).joined(separator: "\n\n")
    }
}
