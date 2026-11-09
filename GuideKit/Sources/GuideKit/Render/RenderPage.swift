/// The document around the sections: the doctype, the head with the inline style, the hero band and the footer.
enum RenderPage {
    static func document(title: String, hero: String, sections: [String]) -> String {
        [
            "<!DOCTYPE html>",
            "<html lang=\"en\">",
            "<head>",
            "<meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<meta name=\"color-scheme\" content=\"light dark\">",
            "<title>\(HTML.escape(title))</title>",
            "<style>",
            GuideHTMLStyle.css,
            "</style>",
            "</head>",
            "<body>",
            hero,
            "<main class=\"wrap\">",
            sections.joined(separator: "\n"),
            "</main>",
            "<footer class=\"colophon\"><p>Made with TABA</p></footer>",
            "</body>",
            "</html>",
            ""
        ].joined(separator: "\n")
    }
}
