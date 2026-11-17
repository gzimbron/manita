import Foundation
import Testing
@testable import ManitaCore

@Suite("ClassicBurst")
struct ClassicBurstTests {
    @Test func classicIsADecodableBurstKind() throws {
        let click = try JSONDecoder().decode(ClickConfig.self, from: Data(#"{"bursts": ["classic", "ring"]}"#.utf8))
        #expect(click.bursts == [.classic, .ring])
        #expect(BurstKind.allCases.contains(.classic))
    }

    @Test func designsWithoutABurstListUseTheClassicBurst() {
        let click = ClickConfig()
        for comic in [false, true] {
            #expect((1...4).map { click.burst(forEffect: $0, comic: comic) } == [.classic, .classic, .classic, .classic])
        }
    }

    @Test func listedKindsStillWork() {
        let click = ClickConfig(bursts: [.rays, .star, .ring])
        #expect((1...3).map { click.burst(forEffect: $0, comic: true) } == [.rays, .star, .ring])
    }

    @Test func classicBurstTakesAsLongAsTheWebOne() {
        #expect(Mood.classicBurstDuration == 0.4)
    }
}
