/// The page's CSS, written into the `<style>` element. Colours are the tokens from `docs/DESIGN.md` (paper, card, ink,
/// coral, steel, gold, deep). Dark mode follows the system. Print always uses the light palette on A4.
///
/// The rules are kept in three parts, in `GuideHTMLStyle+Layout.swift` and `GuideHTMLStyle+Print.swift`, so each
/// stays short enough to read.
enum GuideHTMLStyle {
    static let css = [base, layout, printRules].joined(separator: "\n")

    /// Tokens, typography, the hero band and the checklist.
    static let base = """
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
      --serif: "New York", ui-serif, "Iowan Old Style", Georgia, serif;
      --sans: -apple-system, system-ui, "Helvetica Neue", Arial, sans-serif;
      color-scheme: light dark;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --paper: #1B2129;
        --card: #242C36;
        --ink: #F7F7FF;
        --muted: #AFC2D6;
        --stroke: #36414E;
        --coral: #FE5F55;
        --steel: #9DB6D8;
        --gold: #F0C98E;
        --deep: #12171D;
        --on-deep: #F7F7FF;
      }
      .hero { border-bottom: 1px solid var(--stroke); }
    }

    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }

    body {
      margin: 0;
      background: var(--paper);
      color: var(--ink);
      font-family: var(--sans);
      font-size: 17px;
      line-height: 1.5;
    }

    a {
      color: var(--coral);
      text-decoration: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 3px;
    }

    h1, h2, h3 { margin: 0; line-height: 1.2; }
    h1, h2 { font-family: var(--serif); font-weight: 600; }
    h3 { font-family: var(--serif); font-weight: 400; }
    p { margin: 0; }

    .wrap { max-width: 680px; margin: 0 auto; padding: 0 20px; }

    .eyebrow {
      font-size: 0.75rem;
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: 0.35em;
    }

    .hero {
      background: var(--deep);
      color: var(--on-deep);
      padding: 56px 0 48px;
    }
    .hero h1 { font-size: 2.4rem; margin: 0.3em 0 0.4em; }
    .hero .eyebrow { color: var(--gold); }
    .hero .subtitle { font-size: 1.15rem; margin-bottom: 0.6em; }
    .hero .dates, .hero .summary { font-size: 0.95rem; }
    .hero .summary { margin-top: 0.2em; }
    .hero .tagline {
      font-family: var(--serif);
      font-style: italic;
      font-size: 1.1rem;
      margin-top: 1.4em;
    }

    .checks { margin-top: 32px; }
    .checks h2 { font-size: 1.5rem; margin-bottom: 12px; }
    .checklist { list-style: none; margin: 0; padding: 0; }
    .checklist li {
      position: relative;
      padding: 10px 0 10px 2em;
      border-bottom: 1px solid var(--stroke);
    }
    .checklist li::before {
      content: "";
      position: absolute;
      left: 0;
      top: 12px;
      width: 1.05em;
      height: 1.05em;
      border: 1.5px solid var(--muted);
      border-radius: 4px;
    }

    """
}
