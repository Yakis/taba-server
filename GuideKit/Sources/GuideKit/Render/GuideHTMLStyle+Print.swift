extension GuideHTMLStyle {
    /// The A4 print rules: the light palette, page breaks before each day and before the notes, and no underlines.
    static let printRules = """
    @page { size: A4; margin: 14mm; }

    @media print {
      :root {
        --paper: #F7F7FF;
        --card: #FFFFFF;
        --ink: #1F2731;
        --muted: #495867;
        --stroke: #D3E1EE;
        --coral: #C2372E;
        --steel: #577399;
        --gold: #D3A75F;
        --deep: #495867;
        --on-deep: #F7F7FF;
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
