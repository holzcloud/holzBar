import Foundation
import Testing
@testable import HolzBarCore

@Suite("DownloadScan")
struct DownloadScanTests {
    private func finalNames(_ names: [String]) -> [String] {
        DownloadScan.partials(in: names).map(\.finalName)
    }

    @Test("The marks of Safari, Chrome, Firefox and Opera are recognised, in any case")
    func marks() {
        let names = [
            "Report.pdf.download",
            "Report.pdf.crdownload",
            "Report.pdf.part",
            "Report.pdf.opdownload",
            "X.ZIP.CRDOWNLOAD",
        ]
        let partials = DownloadScan.partials(in: names)
        #expect(partials.map(\.finalName) == ["Report.pdf", "X.ZIP"])
        #expect(partials.map(\.mark) == ["download", "crdownload"])
        for name in names {
            #expect(DownloadScan.partials(in: [name]).count == 1)
        }
        #expect(DownloadScan.partials(in: ["X.ZIP.CRDOWNLOAD"]).first?.mark == "crdownload")
    }

    @Test("Hidden names, a mark that is not last, a mark alone and plain names give nothing")
    func ignored() {
        #expect(DownloadScan.partials(in: [
            ".com.google.Chrome.abc123",
            ".Report.pdf.crdownload",
            "notes.download.txt",
            ".download",
            ".part",
            "readme.txt",
            "download",
            "Makefile",
            "",
            ".",
        ]).isEmpty)
    }

    @Test("Chrome's unconfirmed names are recognised and flagged unnamed")
    func unnamed() {
        let partials = DownloadScan.partials(in: [
            "Unconfirmed 123456.crdownload",
            "Unconfirmed abc.crdownload",
            "Unconfirmed .crdownload",
            "Report.pdf.crdownload",
        ])
        #expect(partials.map(\.finalName) == ["Unconfirmed 123456", "Unconfirmed abc", "Unconfirmed ", "Report.pdf"])
        #expect(partials.map(\.isUnnamed) == [true, false, false, false])
    }

    @Test("Spaces and non-Latin letters stay in the final name")
    func unicode() {
        #expect(finalNames(["Jahresbericht 2026 – Entwurf.pdf.download", "写真 (1).jpg.part", "Über.mp4.crdownload"])
            == ["Jahresbericht 2026 – Entwurf.pdf", "写真 (1).jpg", "Über.mp4"])
    }

    @Test("Each final name is listed once and the order of the input is kept")
    func orderAndDuplicates() {
        #expect(finalNames([
            "b.zip.crdownload",
            "a.zip.part",
            "b.zip.part",
            "c.zip.download",
            "a.zip.download",
        ]) == ["b.zip", "a.zip", "c.zip"])
        #expect(DownloadScan.partials(in: []).isEmpty)
    }
}
