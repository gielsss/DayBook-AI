import Foundation

/// One assignment from a Gradescope course page (student view).
public struct GradescopeAssignment: Equatable {
    public let courseId: String
    public let courseName: String
    public let assignmentId: String?
    public let title: String
    public let status: String          // "No Submission", "Submitted", "8.0 / 10.0", ...
    public let releaseAt: Date?
    public let dueAt: Date?
    public let lateDueAt: Date?

    /// Stable key even when Gradescope shows no assignment link (not yet submittable).
    public var key: String {
        "gradescope-\(courseId)-\(assignmentId ?? CanvasText.fingerprint(title))"
    }

    public var isSubmitted: Bool {
        let s = status.lowercased()
        if s.contains("no submission") || s.contains("missing") { return false }
        return s.contains("submitted") || s.contains("graded") || status.contains(" / ")
    }

    public var url: String {
        if let id = assignmentId { return "https://www.gradescope.com/courses/\(courseId)/assignments/\(id)" }
        return "https://www.gradescope.com/courses/\(courseId)"
    }
}

/// Reads Gradescope (no public student API) through the user's signed-in Gradescope tab:
/// fetches the account page and current course pages from inside the tab and parses them there.
public enum GradescopeReader {
    public static let host = "www.gradescope.com"

    /// Page parsers, shared by the live script and the tests. Pure functions over HTML text.
    /// Selectors follow the student view used by open-source Gradescope tools:
    /// account `div.courseList` / `.courseList--term` / `a[href^="/courses/"]` with `.courseBox--shortname`;
    /// course `tr[role=row]` rows, `submissionTimeChart--releaseDate` / `--dueDate` `datetime` attributes.
    static let parserJS = """
    function ppParseAccount(html) {
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const lists = Array.from(doc.querySelectorAll('.courseList'));
      if (lists.length === 0) return [];
      const heading = Array.from(doc.querySelectorAll('h2.pageHeading, h1.pageHeading')).find(h => h.textContent.trim() === 'Student Courses');
      let list = lists[0];
      if (heading) {
        list = lists.find(l => heading.compareDocumentPosition(l) & Node.DOCUMENT_POSITION_FOLLOWING) || null;
      } else if (doc.querySelector('button.js-createNewCourse')) {
        list = null;
      }
      if (!list) return [];
      const out = []; let term = ''; let termIndex = -1;
      for (const el of list.querySelectorAll('.courseList--term, a[href^="/courses/"]')) {
        if (el.classList.contains('courseList--term')) { term = el.textContent.trim(); termIndex += 1; continue; }
        const short = el.querySelector('.courseBox--shortname');
        if (!short) continue;
        const name = el.querySelector('.courseBox--name');
        out.push({id: el.getAttribute('href').split('/').filter(Boolean).pop(), short: short.textContent.trim(),
                  name: name ? name.textContent.trim() : '', term: term, termIndex: Math.max(termIndex, 0)});
      }
      return out;
    }
    function ppParseCourse(html) {
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const rows = Array.from(doc.querySelectorAll('tr[role="row"]')).filter(r => r.querySelector('.submissionTimeChart--dueDate, .submissionStatus, th.table--primaryLink, .js-submitAssignment'));
      return rows.map(row => {
        const cells = Array.from(row.querySelectorAll('th, td'));
        const first = cells[0] || row;
        const link = first.querySelector('a[href*="/assignments/"]');
        const button = first.querySelector('.js-submitAssignment');
        let id = null;
        if (link) { const parts = link.getAttribute('href').split('/'); const i = parts.indexOf('assignments'); if (i >= 0) id = parts[i + 1]; }
        else if (button) id = button.getAttribute('data-assignment-id');
        const due = Array.from(row.querySelectorAll('.submissionTimeChart--dueDate')).map(t => t.getAttribute('datetime'));
        const release = row.querySelector('.submissionTimeChart--releaseDate');
        return {id: id, title: (link || button || first).textContent.trim(),
                status: cells[1] ? cells[1].textContent.replace(/\\s+/g, ' ').trim() : '',
                release: release ? release.getAttribute('datetime') : null,
                due: due[0] || null, lateDue: due[1] || null};
      }).filter(a => a.title.length > 0);
    }
    """

    /// Runs in the Gradescope tab: reads the account page and every course of the most recent term.
    static var liveJS: String {
        """
        (function(){
          \(parserJS)
          function get(path) { const x = new XMLHttpRequest(); x.open('GET', path, false); x.send(null); return x; }
          const acct = get('/account');
          if (acct.status !== 200 || acct.responseURL.indexOf('/login') >= 0) return JSON.stringify({signedIn: false, status: acct.status});
          const courses = ppParseAccount(acct.responseText).filter(c => c.termIndex === 0);
          const result = {signedIn: true, courses: []};
          for (const c of courses) {
            const page = get('/courses/' + c.id);
            result.courses.push({id: c.id, short: c.short, name: c.name, term: c.term, status: page.status,
                                 assignments: page.status === 200 ? ppParseCourse(page.responseText) : []});
          }
          return JSON.stringify(result);
        })()
        """
    }

    /// Reads Gradescope through `browser`. Throws `CanvasError` with clear setup messages.
    @MainActor
    public static func read(browser: CanvasBrowser) async throws -> [GradescopeAssignment] {
        let transport = CanvasBrowserTransport(browser: browser, canvasHost: host)
        try transport.checkAvailable()
        let source = browser.script(js: liveJS, prefixes: ["https://\(host)/", "https://gradescope.com/"])
        let output = try CanvasBrowserTransport.runAppleScript(source).trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix("PP_NO_TAB") {
            throw CanvasBrowserTransport.noTabError(output, browser: browser, expected: host)
        }
        return try parse(output)
    }

    static func parse(_ output: String) throws -> [GradescopeAssignment] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else {
            throw CanvasError(kind: .invalidResponse, message: "Gradescope returned something unexpected.")
        }
        guard json["signedIn"] as? Bool == true else {
            throw CanvasError(kind: .signInRequired, message: "The Gradescope tab isn't signed in. Sign in to Gradescope in your browser, then sync again.")
        }
        var result: [GradescopeAssignment] = []
        for course in json["courses"] as? [[String: Any]] ?? [] {
            let courseId = course["id"] as? String ?? ""
            let courseName = (course["short"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (course["name"] as? String ?? "Gradescope")
            for a in course["assignments"] as? [[String: Any]] ?? [] {
                result.append(GradescopeAssignment(
                    courseId: courseId,
                    courseName: courseName,
                    assignmentId: a["id"] as? String,
                    title: a["title"] as? String ?? "Gradescope assignment",
                    status: a["status"] as? String ?? "",
                    releaseAt: date(a["release"]),
                    dueAt: date(a["due"]),
                    lateDueAt: date(a["lateDue"])))
            }
        }
        return result
    }

    /// Gradescope `datetime` attributes look like "2026-11-12 23:59:00 -0800" (ISO 8601 also accepted).
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        for format in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm Z"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return CanvasReader.date(text)
    }

    /// Converts to the shared due-item shape used for Canvas, so import rules are identical.
    static func dueItem(_ a: GradescopeAssignment) -> CanvasDueItem {
        var notes = ""
        if let late = a.lateDueAt {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            notes = "Late submissions accepted until \(f.string(from: late))."
        }
        return CanvasDueItem(key: a.key, kind: "gradescope", title: a.title, courseName: a.courseName, dueAt: a.dueAt,
                             pointsPossible: nil, htmlURL: a.url, isSubmitted: a.isSubmitted, isMissing: false, descriptionText: notes)
    }
}
