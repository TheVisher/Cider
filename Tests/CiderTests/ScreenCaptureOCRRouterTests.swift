import Foundation
import Testing
@testable import Cider

@Suite("Screen Capture OCR Router Tests")
struct ScreenCaptureOCRRouterTests {
    @Test("event-like OCR routes to date card with title and location")
    func eventLikeOCRRoutesToDateCardWithTitleAndLocation() throws {
        let route = ScreenCaptureOCRRouter.detectRoute(in: """
        Sponsored
        Pancake Breakfast Meetup
        Saturday, June 6, 2026
        9:30 AM
        Fremont Community Hall
        Get tickets
        """)

        #expect(route.type == .dateCard)
        #expect(route.suggestedTitle == "Pancake Breakfast Meetup")
        #expect(route.suggestedLocation == "Fremont Community Hall")
        #expect(!route.detectedDates.isEmpty)
    }

    @Test("contact-like OCR routes to contact and preserves detected fields")
    func contactLikeOCRRoutesToContactAndPreservesDetectedFields() throws {
        let route = ScreenCaptureOCRRouter.detectRoute(in: """
        Maya Chen
        Product Ops
        maya@example.com
        (415) 555-0198
        """)

        #expect(route.type == .contact)
        #expect(route.suggestedTitle == "Maya Chen")
        #expect(route.detectedEmails.contains("maya@example.com"))
        #expect(route.detectedPhones.contains { $0.contains("415") && $0.contains("0198") })
    }

    @Test("noisy generic OCR falls back to note with useful title")
    func noisyGenericOCRFallsBackToNoteWithUsefulTitle() throws {
        let route = ScreenCaptureOCRRouter.detectRoute(in: """
        Advertisement
        Save
        Interesting product comparison notes
        88 31
        Learn more
        """)

        #expect(route.type == .note)
        #expect(route.suggestedTitle == "Interesting product comparison notes")
        #expect(route.detectedDates.isEmpty)
        #expect(route.detectedEmails.isEmpty)
        #expect(route.detectedPhones.isEmpty)
    }
}
