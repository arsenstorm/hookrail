module ApplicationHelper
  # One place for the class strings every page repeats, so a restyle is one
  # edit rather than twenty-four.
  UI = {
    button_primary: "inline-flex cursor-pointer items-center justify-center rounded-md bg-oxblood-700 px-3 py-1.5 text-sm font-medium text-white hover:bg-oxblood-800 dark:bg-oxblood-600 dark:hover:bg-oxblood-500",
    button_secondary: "inline-flex cursor-pointer items-center justify-center rounded-md px-3 py-1.5 text-sm font-medium text-neutral-700 inset-ring inset-ring-neutral-950/10 hover:bg-neutral-950/5 dark:text-neutral-300 dark:inset-ring-white/10 dark:hover:bg-white/5",
    button_danger: "inline-flex cursor-pointer items-center justify-center rounded-md px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950/40",
    danger_link: "cursor-pointer text-sm font-medium text-red-700 hover:text-red-800 dark:text-red-400 dark:hover:text-red-300",
    input: "block w-full rounded-md bg-transparent px-3 py-1.5 text-sm text-neutral-950 inset-ring inset-ring-neutral-950/15 placeholder:text-neutral-400 focus:outline-2 focus:outline-offset-2 focus:outline-neutral-950/40 dark:text-white dark:inset-ring-white/15 dark:focus:outline-white/40",
    select: "min-w-0 cursor-pointer appearance-none rounded-md bg-transparent py-1.5 pr-8 pl-2.5 text-sm text-neutral-950 inset-ring inset-ring-neutral-950/15 focus:outline-2 focus:outline-offset-2 focus:outline-neutral-950/40 dark:text-white dark:inset-ring-white/15 dark:focus:outline-white/40",
    label: "block text-sm font-medium text-neutral-950 dark:text-white",
    hint: "text-sm text-neutral-500 dark:text-neutral-400",
    card: "rounded-xl elevated",
    badge: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap",
    badge_neutral: "bg-neutral-950/5 text-neutral-600 dark:bg-white/10 dark:text-neutral-300",
    badge_green: "bg-emerald-600/10 text-emerald-800 dark:bg-emerald-400/10 dark:text-emerald-300",
    badge_red: "bg-red-600/10 text-red-800 dark:bg-red-400/10 dark:text-red-300",
    badge_amber: "bg-amber-500/15 text-amber-800 dark:bg-amber-400/10 dark:text-amber-300",
    heading: "text-2xl font-semibold tracking-tight text-balance text-neutral-950 dark:text-white",
    subheading: "text-xl font-semibold tracking-tight text-neutral-950 dark:text-white",
    section: "text-sm font-semibold text-neutral-950 dark:text-white",
    link: "font-medium text-oxblood-700 hover:text-oxblood-900 dark:text-oxblood-300 dark:hover:text-oxblood-200",
    muted_link: "text-sm text-neutral-500 hover:text-neutral-950 dark:text-neutral-400 dark:hover:text-white",
    th: "py-2.5 text-left text-sm font-medium whitespace-nowrap text-neutral-500 dark:text-neutral-400",
    td: "py-2.5 text-sm text-neutral-950 dark:text-white",
    td_muted: "py-2.5 text-sm text-neutral-600 dark:text-neutral-400",
    table_head: "border-b border-neutral-950/10 dark:border-white/10",
    table_body: "divide-y divide-neutral-950/5 dark:divide-white/5",
    # Scrollable tables bleed to the page edge; the padding mirrors the main
    # container's so the first and last column line up with the heading again.
    scroller: "-mx-5 -my-2 overflow-x-auto whitespace-nowrap lg:mx-0",
    scroller_inner: "inline-block min-w-full px-5 py-2 align-middle lg:px-0"
  }.freeze

  def ui(key) = UI.fetch(key)

  # Heroicons 16px solid, kept as inner markup so multi-path glyphs stay verbatim.
  NAV_ICONS = {
    dashboard: %(<path d="M12 2a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1V3a1 1 0 0 0-1-1h-1ZM6.5 6a1 1 0 0 1 1-1h1a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1V6ZM2 9a1 1 0 0 1 1-1h1a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V9Z"/>),
    events: %(<path fill-rule="evenodd" d="M9.58 1.077a.75.75 0 0 1 .405.82L9.165 6h4.085a.75.75 0 0 1 .567 1.241l-6.5 7.5a.75.75 0 0 1-1.302-.638L6.835 10H2.75a.75.75 0 0 1-.567-1.241l6.5-7.5a.75.75 0 0 1 .897-.182Z" clip-rule="evenodd"/>),
    issues: %(<path fill-rule="evenodd" d="M6.701 2.25c.577-1 2.02-1 2.598 0l5.196 9a1.5 1.5 0 0 1-1.299 2.25H2.804a1.5 1.5 0 0 1-1.3-2.25l5.197-9ZM8 4a.75.75 0 0 1 .75.75v3a.75.75 0 1 1-1.5 0v-3A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd"/>),
    sources: %(<path d="M8.75 2.75a.75.75 0 0 0-1.5 0v5.69L5.03 6.22a.75.75 0 0 0-1.06 1.06l3.5 3.5a.75.75 0 0 0 1.06 0l3.5-3.5a.75.75 0 0 0-1.06-1.06L8.75 8.44V2.75Z"/><path d="M3.5 9.75a.75.75 0 0 0-1.5 0v1.5A2.75 2.75 0 0 0 4.75 14h6.5A2.75 2.75 0 0 0 14 11.25v-1.5a.75.75 0 0 0-1.5 0v1.5c0 .69-.56 1.25-1.25 1.25h-6.5c-.69 0-1.25-.56-1.25-1.25v-1.5Z"/>),
    destinations: %(<path d="M2.87 2.298a.75.75 0 0 0-.812 1.021L3.39 6.624a1 1 0 0 0 .928.626H8.25a.75.75 0 0 1 0 1.5H4.318a1 1 0 0 0-.927.626l-1.333 3.305a.75.75 0 0 0 .811 1.022 24.89 24.89 0 0 0 11.668-5.115.75.75 0 0 0 0-1.175A24.89 24.89 0 0 0 2.869 2.298Z"/>),
    connections: %(<path fill-rule="evenodd" d="M8.914 6.025a.75.75 0 0 1 1.06 0 3.5 3.5 0 0 1 0 4.95l-2 2a3.5 3.5 0 0 1-5.396-4.402.75.75 0 0 1 1.251.827 2 2 0 0 0 3.085 2.514l2-2a2 2 0 0 0 0-2.828.75.75 0 0 1 0-1.06Z" clip-rule="evenodd"/><path fill-rule="evenodd" d="M7.086 9.975a.75.75 0 0 1-1.06 0 3.5 3.5 0 0 1 0-4.95l2-2a3.5 3.5 0 0 1 5.396 4.402.75.75 0 0 1-1.251-.827 2 2 0 0 0-3.085-2.514l-2 2a2 2 0 0 0 0 2.828.75.75 0 0 1 0 1.06Z" clip-rule="evenodd"/>),
    members: %(<path d="M8 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM12.735 14c.618 0 1.093-.561.872-1.139a6.002 6.002 0 0 0-11.215 0c-.22.578.254 1.139.872 1.139h9.47Z"/>),
    alerts: %(<path fill-rule="evenodd" d="M8 1a4 4 0 0 0-4 4v2.379a1.5 1.5 0 0 1-.44 1.06L2.294 9.707A1 1 0 0 0 3 11.414h10a1 1 0 0 0 .707-1.707L12.44 8.44A1.5 1.5 0 0 1 12 7.38V5a4 4 0 0 0-4-4Z" clip-rule="evenodd"/><path d="M6 12.75a2 2 0 0 0 4 0H6Z"/>),
    retention: %(<path fill-rule="evenodd" d="M8 14A6 6 0 1 0 8 2a6 6 0 0 0 0 12Zm.75-9.25a.75.75 0 0 0-1.5 0V8c0 .414.336.75.75.75h2.5a.75.75 0 0 0 0-1.5h-1.75V4.75Z" clip-rule="evenodd"/>),
    projects: %(<path d="M3.75 3A1.75 1.75 0 0 0 2 4.75v6.5c0 .966.784 1.75 1.75 1.75h8.5A1.75 1.75 0 0 0 14 11.25v-5a1.75 1.75 0 0 0-1.75-1.75H8.56L7.4 3.4A1.5 1.5 0 0 0 6.34 3H3.75Z"/>),
    gear: %(<path fill-rule="evenodd" d="M6.455 1.45A.5.5 0 0 1 6.952 1h2.096a.5.5 0 0 1 .497.45l.186 1.858a4.996 4.996 0 0 1 1.466.848l1.703-.769a.5.5 0 0 1 .639.206l1.047 1.814a.5.5 0 0 1-.14.656l-1.517 1.09a5.026 5.026 0 0 1 0 1.694l1.516 1.09a.5.5 0 0 1 .141.656l-1.047 1.814a.5.5 0 0 1-.639.206l-1.703-.768c-.433.36-.928.65-1.466.847l-.186 1.858a.5.5 0 0 1-.497.45H6.952a.5.5 0 0 1-.497-.45l-.186-1.858a4.993 4.993 0 0 1-1.466-.848l-1.703.769a.5.5 0 0 1-.639-.206l-1.047-1.814a.5.5 0 0 1 .14-.656l1.517-1.09a5.033 5.033 0 0 1 0-1.694l-1.516-1.09a.5.5 0 0 1-.141-.656L2.46 3.593a.5.5 0 0 1 .639-.206l1.703.769c.433-.36.928-.65 1.466-.848l.186-1.858Zm-.177 7.567-.022-.012a2 2 0 1 1 3.53-1.892l.01.024a2 2 0 1 1-3.518 1.88Z" clip-rule="evenodd"/>),
    # Not in the sidebar; the marketing feature grid uses the same 16px style.
    shield: %(<path fill-rule="evenodd" d="M8.5 1.709a.75.75 0 0 0-1 0 8.963 8.963 0 0 1-4.84 2.217.75.75 0 0 0-.654.72 10.499 10.499 0 0 0 5.647 9.672.75.75 0 0 0 .694-.001 10.499 10.499 0 0 0 5.647-9.672.75.75 0 0 0-.654-.719A8.963 8.963 0 0 1 8.5 1.71Zm2.34 5.504a.75.75 0 0 0-1.18-.926L7.394 9.17l-1.156-.99a.75.75 0 1 0-.976 1.138l1.75 1.5a.75.75 0 0 0 1.078-.106l2.75-3.5Z" clip-rule="evenodd"/>),
    lock: %(<path fill-rule="evenodd" d="M8 1a3.5 3.5 0 0 0-3.5 3.5V7A1.5 1.5 0 0 0 3 8.5v5A1.5 1.5 0 0 0 4.5 15h7a1.5 1.5 0 0 0 1.5-1.5v-5A1.5 1.5 0 0 0 11.5 7V4.5A3.5 3.5 0 0 0 8 1Zm2 6V4.5a2 2 0 1 0-4 0V7h4Z" clip-rule="evenodd"/>),
    key: %(<path fill-rule="evenodd" d="M8 7a5 5 0 1 1 3.61 4.804l-1.903 1.903A1 1 0 0 1 9 14H8v1a1 1 0 0 1-1 1H6v1a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1v-2a1 1 0 0 1 .293-.707L8.196 8.39A5.002 5.002 0 0 1 8 7Zm5-3a.75.75 0 0 0 0 1.5A1.5 1.5 0 0 1 14.5 7 .75.75 0 0 0 16 7a3 3 0 0 0-3-3Z" clip-rule="evenodd"/>)
  }.freeze

  def nav_icon(key)
    tag.svg(NAV_ICONS.fetch(key).html_safe, viewBox: "0 0 16 16",
            class: "size-4 shrink-0 fill-current", "aria-hidden": "true")
  end

  # Sidebar nav: [[section label, [[name, path, icon], ...]]]. A section
  # disappears when the current membership can't reach anything in it.
  def sidebar_sections
    sections = []
    if Current.project
      sections << [ "Monitor", [ [ "Dashboard", dashboard_path, :dashboard ], [ "Events", events_path, :events ],
                                 [ "Issues", issues_path, :issues ] ] ]
      sections << [ "Configure", [ [ "Sources", sources_path, :sources ], [ "Destinations", destinations_path, :destinations ],
                                   [ "Connections", connections_path, :connections ] ] ]
    end
    sections
  end

  # Monitor pages kept within reach from the settings area, so /org isn't a
  # dead end. Dashboard heads the group but is rendered by hand: /app prefixes
  # every app path, so the loop's start_with? aria-current would misfire.
  def settings_monitor_items
    [ [ "Events", events_path, :events ], [ "Issues", issues_path, :issues ] ]
  end

  # The org settings pages, in sidebar order. Shared by the settings sidebar
  # and the mobile nav.
  def settings_nav_items
    [ [ "Members", members_path, :members ], [ "Alerts", alert_webhook_path, :alerts ],
      [ "Data retention", retention_path, :retention ], [ "API keys", api_keys_path, :key ],
      [ "Projects", projects_path, :projects ] ]
  end

  # Everything under /org is a settings page, which swaps the sidebar.
  def settings_area? = request.path.start_with?("/org")

  # Path match ignores the query string so ?window=7d keeps Dashboard lit, and
  # nested pages (an event, a source) keep their section lit.
  def nav_item_classes(path)
    base = "flex items-center gap-2 rounded-md px-2.5 py-1.5 text-sm font-medium"
    active = path == dashboard_path ? request.path == path : request.path.start_with?(path)
    if active
      "#{base} bg-oxblood-700/10 text-oxblood-900 dark:bg-oxblood-500/15 dark:text-oxblood-200"
    else
      "#{base} text-neutral-600 hover:bg-neutral-950/5 hover:text-neutral-950 dark:text-neutral-400 dark:hover:bg-white/5 dark:hover:text-white"
    end
  end
end
