extension GuideHTMLStyle {
    /// The A4 print rules: the light palette, page breaks before each day and before the notes, and no underlines.
    static let printRules = """
    @page { size: A4; margin: 14mm; }

    @media print {
      :root {
        --paper: #F7F2E9;
        --card: #FFFDF8;
        --ink: #172A2B;
        --muted: #6C655B;
        --stroke: #DDD2C2;
        --wine: #6E2A3C;
        --brick: #A14B30;
        --gold: #D3A75F;
        --deep: #102528;
        --on-deep: #F7F0E3;
      }
      body { font-size: 10.5pt; }
      .hero { border-bottom: 0; }
      .wrap { max-width: none; }
      .hero, .eyebrow, .dot, .rail::before, .card, .tag, .badge, .checklist li::before {
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }
      a { text-decoration: none; }
      .day, .part { break-before: page; }
      .day, .list, .part { margin-top: 0; }
      .row, .card, .checklist li, .fact, .list-rows li { break-inside: avoid; }
      h2, h3 { break-after: avoid; }
      .colophon { padding-bottom: 0; }
    }
    """
}
