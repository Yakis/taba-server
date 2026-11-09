extension GuideHTMLStyle {
    /// The day, timeline, card, place, list, note and source rules.
    static let layout = """
    .day { margin-top: 48px; }
    .day-head h2 { font-size: 1.75rem; margin-bottom: 0.4em; }
    .day-head .summary { margin-bottom: 0.5em; }
    .conditions {
      font-size: 0.9rem;
      color: var(--muted);
      font-variant-numeric: tabular-nums;
    }

    .timeline { list-style: none; margin: 24px 0 0; padding: 0; }
    .row {
      display: grid;
      grid-template-columns: 3.6em 1.5rem minmax(0, 1fr);
    }
    .time {
      font-size: 0.95rem;
      font-weight: 600;
      padding-top: 16px;
      font-variant-numeric: tabular-nums;
    }
    .rail { position: relative; }
    .rail::before {
      content: "";
      position: absolute;
      top: 0;
      bottom: 0;
      left: 50%;
      width: 1px;
      margin-left: -0.5px;
      background: var(--stroke);
    }
    .dot {
      position: absolute;
      top: 21px;
      left: 50%;
      width: 0.65rem;
      height: 0.65rem;
      margin-left: -0.325rem;
      border-radius: 50%;
      background: var(--ink);
    }
    .quiet .dot {
      top: 23px;
      width: 0.45rem;
      height: 0.45rem;
      margin-left: -0.225rem;
      background: var(--muted);
    }
    .meal .dot { background: var(--steel); }
    .drink .dot { background: var(--coral); }
    .meal .eyebrow { color: var(--steel); }
    .drink .eyebrow { color: var(--coral); }

    .leg-text {
      align-self: center;
      font-size: 0.85rem;
      color: var(--muted);
      padding: 4px 0 12px 0;
      font-variant-numeric: tabular-nums;
    }

    .card {
      background: var(--card);
      border: 1px solid var(--stroke);
      border-radius: 20px;
      padding: 16px;
      margin-bottom: 12px;
    }
    .card.optional {
      background: transparent;
      border-style: dashed;
    }
    .stop h3 { font-size: 1.2rem; margin-bottom: 0.25em; }
    .stop h3 a { color: inherit; text-decoration: none; }
    .stop-place { font-size: 0.9rem; color: var(--muted); margin-bottom: 0.4em; }
    .body { margin-bottom: 0.6em; }
    .meta { font-size: 0.9rem; color: var(--muted); font-variant-numeric: tabular-nums; }
    .alt { font-size: 0.9rem; color: var(--muted); margin-top: 0.6em; }
    .tag {
      display: inline-block;
      margin-left: 0.6em;
      padding: 0 0.5em;
      border: 1px solid var(--stroke);
      border-radius: 999px;
      color: var(--muted);
    }
    .badge {
      display: inline-block;
      margin-left: 0.4em;
      padding: 0 0.6em;
      border: 1px solid var(--coral);
      border-radius: 999px;
      color: var(--coral);
      font-size: 0.8rem;
      text-decoration: none;
    }
    .info-mark { font-style: normal; }

    .part { margin-top: 48px; }
    .list { margin-top: 40px; }
    .list h2 { font-size: 1.5rem; margin-bottom: 0.2em; }
    .caption { color: var(--muted); font-style: italic; margin-bottom: 0.6em; }
    .list-rows { list-style: none; margin: 0; padding: 0; }
    .list-rows li {
      padding: 12px 0;
      border-bottom: 1px solid var(--stroke);
    }
    .row-name { font-weight: 600; }
    .row-meta { font-size: 0.9rem; color: var(--muted); margin-top: 2px; }

    .place { margin-top: 0; }
    .place h3 { font-size: 1.35rem; margin-bottom: 0.25em; }
    .place .blurb { margin-bottom: 0.8em; }
    .info {
      display: grid;
      grid-template-columns: max-content minmax(0, 1fr);
      gap: 8px 16px;
      margin: 0 0 0.9em;
      font-size: 0.92rem;
    }
    .info dt { color: var(--muted); }
    .info dd { margin: 0; }
    .hours { list-style: none; margin: 0; padding: 0; }
    .note { display: block; font-size: 0.85rem; color: var(--muted); }
    .fact { font-size: 0.92rem; margin-top: 0.5em; }
    .source { font-size: 0.85rem; }
    .muted { color: var(--muted); }

    .trip-note h3 { font-size: 1.1rem; margin-bottom: 0.3em; }
    #good-to-know { margin-top: 40px; }
    #good-to-know h2, #tasting h2 { font-size: 1.5rem; margin-bottom: 12px; }
    .facts { margin: 0; padding-left: 1.2em; }
    .facts li { margin-bottom: 0.6em; }
    #tasting { margin-top: 40px; }
    .taste-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(190px, 1fr));
      gap: 12px;
    }
    .taste { margin-bottom: 0; }
    .taste h3 { font-size: 1.1rem; margin-bottom: 0.3em; }
    .taste p { font-size: 0.92rem; color: var(--muted); }

    .sources { margin-top: 40px; }
    .sources ol { margin: 0; padding-left: 1.3em; font-size: 0.92rem; }
    .sources li { margin-bottom: 0.5em; }

    .colophon {
      text-align: center;
      color: var(--muted);
      font-size: 0.8rem;
      padding: 48px 20px 56px;
    }

    """
}
