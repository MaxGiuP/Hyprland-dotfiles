#!/usr/bin/env bash
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
COLORS_JSON="$STATE_DIR/user/generated/colors.json"

if [ ! -f "$COLORS_JSON" ] || ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

gtk3_dir="$XDG_CONFIG_HOME/gtk-3.0"
gtk4_dir="$XDG_CONFIG_HOME/gtk-4.0"
materialyou_dir="$HOME/.themes/MaterialYou"
mkdir -p "$gtk3_dir" "$gtk4_dir"
mkdir -p "$gtk3_dir/quickshell" "$gtk4_dir/quickshell"

get_color() {
  local key="$1"
  local fallback="$2"
  local value
  value=$(jq -r --arg k "$key" '.[$k] // empty' "$COLORS_JSON")
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf '%s' "$fallback"
  else
    printf '%s' "$value"
  fi
}

# ── Surface scale (Material You depth hierarchy) ──────────────────────────────
bg=$(get_color "background" "#121212")
on_bg=$(get_color "on_background" "#e6e1e5")
surface=$(get_color "surface" "$bg")
on_surface=$(get_color "on_surface" "$on_bg")
on_surface_variant=$(get_color "on_surface_variant" "#cac4d0")
surface_bright=$(get_color "surface_bright" "#3a3635")
surface_variant=$(get_color "surface_variant" "#49454f")
container_lowest=$(get_color "surface_container_lowest" "#0e0e0e")
container_low=$(get_color "surface_container_low" "#1e1e1e")
container=$(get_color "surface_container" "#252525")
container_high=$(get_color "surface_container_high" "#2f2b30")
container_highest=$(get_color "surface_container_highest" "#3a3540")
surface_tint=$(get_color "surface_tint" "#bb86fc")

# ── Primary accent ────────────────────────────────────────────────────────────
primary=$(get_color "primary" "#bb86fc")
on_primary=$(get_color "on_primary" "#21005d")
primary_container=$(get_color "primary_container" "#4a0080")
on_primary_container=$(get_color "on_primary_container" "#eaddff")
primary_fixed=$(get_color "primary_fixed" "#eaddff")
primary_fixed_dim=$(get_color "primary_fixed_dim" "$primary")
inverse_primary=$(get_color "inverse_primary" "#6200ea")

# ── Secondary ─────────────────────────────────────────────────────────────────
secondary=$(get_color "secondary" "#03dac6")
on_secondary=$(get_color "on_secondary" "#003730")
secondary_container=$(get_color "secondary_container" "#005048")
on_secondary_container=$(get_color "on_secondary_container" "#cefaf8")

# ── Tertiary ──────────────────────────────────────────────────────────────────
tertiary=$(get_color "tertiary" "#78dc77")
on_tertiary=$(get_color "on_tertiary" "#003910")
tertiary_container=$(get_color "tertiary_container" "#1f5c21")
on_tertiary_container=$(get_color "on_tertiary_container" "#93f991")

# ── Error ─────────────────────────────────────────────────────────────────────
error=$(get_color "error" "#f2b8b5")
on_error=$(get_color "on_error" "#601410")
error_container=$(get_color "error_container" "#8c1d18")
on_error_container=$(get_color "on_error_container" "#f9dedc")

# ── Outlines ──────────────────────────────────────────────────────────────────
outline=$(get_color "outline" "#938f99")
outline_variant=$(get_color "outline_variant" "#49454f")

# ── Inverse ───────────────────────────────────────────────────────────────────
inverse_surface=$(get_color "inverse_surface" "#e6e1e5")
inverse_on_surface=$(get_color "inverse_on_surface" "#313033")

# ── Semantic status: tertiary=success (greener), primary_container=warning ────
# tertiary is the "cooler/greener" tone — maps naturally to success/positive
# secondary_container maps to warning — warm, amber-adjacent in warm palettes
success_color=$tertiary
on_success=$on_tertiary
success_container=$tertiary_container
on_success_container=$on_tertiary_container

warning_color=$secondary
on_warning=$on_secondary
warning_container=$secondary_container
on_warning_container=$on_secondary_container

# ── Compute selection text color (contrast-aware) ─────────────────────────────
# Returns #ffffff for dark backgrounds, #1c1b1f for light backgrounds
get_contrast_text_color() {
  local hex="${1#\#}"
  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))
  local brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
  if [ "$brightness" -gt 128 ]; then
    printf '#1c1b1f'
  else
    printf '#ffffff'
  fi
}
selection_fg=$(get_contrast_text_color "$primary")

# ── Generate CSS ──────────────────────────────────────────────────────────────
colors_css=$(cat <<CSS
/*
 * Material You GTK/libadwaita dynamic color bridge
 * Generated from: $COLORS_JSON
 *
 * Design: full Material You surface-scale depth hierarchy.
 * surface_container_lowest < background = surface < container_low <
 * container < container_high < container_highest < surface_bright
 */

/* ════════════════════════════════════════════════════════════════════════════
 * 1. LIBADWAITA CSS CUSTOM PROPERTIES
 *    User-stylesheet :root beats libadwaita's author :root, so our Material
 *    You values win over libadwaita's hard-coded defaults.
 * ════════════════════════════════════════════════════════════════════════════ */
:root {
  /* ── Surface / window ──────────────────────────────────────────────────── */
  --window-bg-color:                 ${bg};
  --window-fg-color:                 ${on_bg};
  --view-bg-color:                   ${surface};
  --view-fg-color:                   ${on_surface};

  /* ── Surface containers (elevation layers) ─────────────────────────────── */
  --headerbar-bg-color:              ${container_high};
  --headerbar-fg-color:              ${on_surface};
  --headerbar-border-color:          ${outline_variant};
  --headerbar-backdrop-color:        ${container};
  --headerbar-shade-color:           ${outline_variant};
  --headerbar-darker-shade-color:    ${container_low};

  --sidebar-bg-color:                ${bg};
  --sidebar-fg-color:                ${on_surface};
  --sidebar-backdrop-color:          ${bg};
  --sidebar-border-color:            alpha(${outline_variant}, 0.3);
  --secondary-sidebar-bg-color:      ${container};
  --secondary-sidebar-fg-color:      ${on_surface};
  --secondary-sidebar-backdrop-color:${container_low};

  --card-bg-color:                   ${container};
  --card-fg-color:                   ${on_surface};
  --dialog-bg-color:                 ${container_high};
  --dialog-fg-color:                 ${on_surface};
  --popover-bg-color:                ${container_highest};
  --popover-fg-color:                ${on_surface};
  --thumbnail-bg-color:              ${container};
  --thumbnail-fg-color:              ${on_surface};

  /* ── Accent ────────────────────────────────────────────────────────────── */
  --accent-color:                    ${primary};
  --accent-bg-color:                 ${primary};
  --accent-fg-color:                 ${on_primary};

  /* ── Status ────────────────────────────────────────────────────────────── */
  --destructive-color:               ${error};
  --destructive-bg-color:            ${error};
  --destructive-fg-color:            ${on_error};

  --success-color:                   ${success_color};
  --success-bg-color:                ${success_container};
  --success-fg-color:                ${on_success_container};

  --warning-color:                   ${warning_color};
  --warning-bg-color:                ${warning_container};
  --warning-fg-color:                ${on_warning_container};

  --error-color:                     ${error};
  --error-bg-color:                  ${error_container};
  --error-fg-color:                  ${on_error_container};

  /* ── Misc libadwaita tokens ─────────────────────────────────────────────── */
  --border-opacity:                  8%;
  --dim-label-opacity:               0.55;
  --scrollbar-outline-color:         transparent;

}

/* ════════════════════════════════════════════════════════════════════════════
 * 2. GTK @define-color TOKENS
 *    Consumed by GTK3, WhiteSur, and older libadwaita-adjacent code.
 * ════════════════════════════════════════════════════════════════════════════ */

/* Accent */
@define-color accent_color           ${primary};
@define-color accent_bg_color        ${primary};
@define-color accent_fg_color        ${on_primary};

/* Destructive */
@define-color destructive_color      ${error};
@define-color destructive_bg_color   ${error};
@define-color destructive_fg_color   ${on_error};

/* Success (tertiary = greener tone) */
@define-color success_color          ${success_color};
@define-color success_bg_color       ${success_container};
@define-color success_fg_color       ${on_success_container};

/* Warning (secondary = warm/amber tone) */
@define-color warning_color          ${warning_color};
@define-color warning_bg_color       ${warning_container};
@define-color warning_fg_color       ${on_warning_container};

/* Error */
@define-color error_color            ${error};
@define-color error_bg_color         ${error_container};
@define-color error_fg_color         ${on_error_container};

/* Window & view */
@define-color window_bg_color        ${bg};
@define-color window_fg_color        ${on_bg};
@define-color view_bg_color          ${surface};
@define-color view_fg_color          ${on_surface};

/* Headerbar */
@define-color headerbar_bg_color     ${container_high};
@define-color headerbar_fg_color     ${on_surface};
@define-color headerbar_border_color ${outline_variant};
@define-color headerbar_backdrop_color ${container};
@define-color headerbar_shade_color  ${outline_variant};
@define-color headerbar_darker_shade_color ${container_low};

/* Sidebar */
@define-color sidebar_bg_color       ${container_low};
@define-color sidebar_fg_color       ${on_surface};
@define-color sidebar_backdrop_color ${bg};
@define-color secondary_sidebar_bg_color   ${container};
@define-color secondary_sidebar_fg_color   ${on_surface};
@define-color secondary_sidebar_backdrop_color ${container_low};

/* Card / dialog / popover */
@define-color card_bg_color          ${container};
@define-color card_fg_color          ${on_surface};
@define-color dialog_bg_color        ${container_high};
@define-color dialog_fg_color        ${on_surface};
@define-color popover_bg_color       ${container_highest};
@define-color popover_fg_color       ${on_surface};
@define-color thumbnail_bg_color     ${container};
@define-color thumbnail_fg_color     ${on_surface};

/* GTK3 legacy names */
@define-color base_color             ${surface};
@define-color text_color             ${on_surface};
@define-color bg_color               ${bg};
@define-color theme_bg_color         ${bg};
@define-color theme_fg_color         ${on_bg};
@define-color theme_base_color       ${surface};
@define-color theme_text_color       ${on_surface};
@define-color theme_selected_bg_color      ${primary};
@define-color theme_selected_fg_color      ${on_primary};
@define-color theme_unfocused_bg_color     ${container_low};
@define-color theme_unfocused_base_color   ${surface};
@define-color theme_unfocused_fg_color     ${on_bg};
@define-color theme_unfocused_text_color   ${on_surface};
@define-color theme_unfocused_selected_bg_color  ${secondary_container};
@define-color theme_unfocused_selected_fg_color  ${on_secondary_container};
@define-color insensitive_bg_color   ${container_low};
@define-color insensitive_fg_color   ${on_surface_variant};
@define-color insensitive_base_color ${surface};
@define-color borders                ${outline_variant};
@define-color unfocused_borders      ${outline_variant};
@define-color link_color             ${primary};
@define-color visited_link_color     ${secondary};
@define-color placeholder_text_color ${on_surface_variant};
@define-color content_view_bg        ${surface};
@define-color text_view_bg           ${surface};
@define-color entry_bg_color         ${container};
@define-color tooltip_bg_color       ${surface_bright};
@define-color tooltip_fg_color       ${on_surface};

/* Bare semantic aliases — many GTK widgets and our own rules reference these */
@define-color on_surface                  ${on_surface};
@define-color on_surface_variant          ${on_surface_variant};
@define-color surface_bright              ${surface_bright};
@define-color shadow_color                ${container_lowest};

/* Full Material You palette — exposed for any custom widget code */
@define-color primary_color               ${primary};
@define-color on_primary_color            ${on_primary};
@define-color primary_container_color     ${primary_container};
@define-color on_primary_container_color  ${on_primary_container};
@define-color secondary_color             ${secondary};
@define-color on_secondary_color          ${on_secondary};
@define-color secondary_container_color   ${secondary_container};
@define-color on_secondary_container_color ${on_secondary_container};
@define-color tertiary_color              ${tertiary};
@define-color on_tertiary_color           ${on_tertiary};
@define-color tertiary_container_color    ${tertiary_container};
@define-color on_tertiary_container_color ${on_tertiary_container};
@define-color error_container_color       ${error_container};
@define-color on_error_container_color    ${on_error_container};
@define-color outline_color              ${outline};
@define-color outline_variant_color      ${outline_variant};
@define-color surface_variant_color      ${surface_variant};
@define-color on_surface_variant_color   ${on_surface_variant};
@define-color surface_bright_color       ${surface_bright};
@define-color surface_container_lowest   ${container_lowest};
@define-color surface_container_low      ${container_low};
@define-color surface_container          ${container};
@define-color surface_container_high     ${container_high};
@define-color surface_container_highest  ${container_highest};
@define-color inverse_surface_color      ${inverse_surface};
@define-color inverse_on_surface_color   ${inverse_on_surface};
@define-color inverse_primary_color      ${inverse_primary};
@define-color surface_tint_color         ${surface_tint};

/* ════════════════════════════════════════════════════════════════════════════
 * 3. WINDOW & BACKGROUND
 *    Set the CSS custom properties at the window/root level so every
 *    var(--window-bg-color) etc. reference inside the window resolves
 *    to our colors even before the per-widget rules kick in.
 * ════════════════════════════════════════════════════════════════════════════ */

window,
window.background,
.background,
:root {
  --window-bg-color:    ${container_low};
  --window-fg-color:    ${on_bg};
  --view-bg-color:      ${container_low};
  --view-fg-color:      ${on_surface};
  --sidebar-bg-color:   ${container_low};
  --sidebar-fg-color:   ${on_surface};
  --card-bg-color:      ${container};
  --card-fg-color:      ${on_surface};
  --dialog-bg-color:    ${container_high};
  --dialog-fg-color:    ${on_surface};
  --popover-bg-color:   ${container_highest};
  --popover-fg-color:   ${on_surface};
  --accent-color:       ${primary};
  --accent-bg-color:    ${primary};
  --accent-fg-color:    ${on_primary};
}

window,
window.background,
.background {
  background-color: ${container_low} !important;
  background-image: none !important;
  color: ${on_bg} !important;
}

/* libadwaita 1.4–1.8 scaffold widgets */
toolbarview {
  background-color: ${container_low} !important;
  background-image: none !important;
}

navigationview > stack,
navigationsplitview > .content-bin {
  background-color: ${container_low} !important;
  background-image: none !important;
}
navigationsplitview > .sidebar-bin {
  background-color: ${bg} !important;
  background-image: none !important;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 4. VIEWS & SCROLLED WINDOWS
 * ════════════════════════════════════════════════════════════════════════════ */

.view,
iconview,
iconview > cell,
textview,
textview > text,
columnview,
listview,
treeview,
treeview.view,
layout,
fixed {
  background-color: ${surface} !important;
  color: ${on_surface} !important;
}

/* ── Scrolledwindow children — catches ALL content views universally ───────
 * scrolledwindow > * catches ANY GtkScrollable direct child, including
 * EelCanvas/NemoIconContainer which implements GtkScrollable and is placed
 * as a DIRECT child of GtkScrolledWindow (no intermediate GtkViewport).
 * Without this rule, nemo-canvas-item is invisible to viewport selectors. */
scrolledwindow > *,
scrolledwindow > viewport,
scrolledwindow > viewport > *,
scrolledwindow > treeview,
scrolledwindow > iconview,
scrolledwindow > layout,
scrolledwindow > fixed,
scrolledwindow > textview,
viewport,
viewport > * {
  background-color: ${surface} !important;
  background-image: none !important;
  color: ${on_surface} !important;
}

/* ── nemo-canvas-item: CSS node name registered by NemoIconContainer ───────
 * NemoIconContainer calls gtk_widget_class_set_css_name("nemo-canvas-item")
 * so it matches this selector specifically, even though it inherits GtkLayout.
 * This is the definitive fix for the white Nemo icon view background. */
nemo-canvas-item {
  background-color: ${surface} !important;
  background-image: none !important;
  color: ${on_surface} !important;
}

/* Row/cell selection states */
treeview:selected,
treeview > row:selected,
iconview:selected,
iconview > cell:selected,
row:selected {
  background-color: ${primary} !important;
  color: ${on_primary} !important;
}
treeview:selected:focus,
iconview:selected:focus,
row:selected:focus-within {
  background-color: ${primary} !important;
  color: ${on_primary} !important;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 5. HEADERBAR, TITLEBAR & ALL LIBADWAITA 1.8 HEADER-CLASS WIDGETS
 *
 *    libadwaita 1.8 uses var(--headerbar-bg-color) on these widgets:
 *      headerbar, tabbar .box, searchbar > revealer > box,
 *      actionbar > revealer > box, toolbarview > .top-bar.raised,
 *      toolbarview > .bottom-bar.raised
 *
 *    Strategy: set the CSS custom property directly on each element AND
 *    override background-color with !important so we win regardless of
 *    whether the @define-color cascade resolves correctly.
 * ════════════════════════════════════════════════════════════════════════════ */

/* Shared custom-property injection — forces var(--headerbar-bg-color) to our
 * value on every element that uses it, even if :root inheritance is blocked. */
headerbar,
.titlebar,
headerbar.titlebar,
.titlebar.horizontal,
tabbar .box,
tabbar tab:checked,
searchbar > revealer > box,
actionbar > revealer > box,
toolbarview > .top-bar,
toolbarview > .top-bar.raised,
toolbarview > .bottom-bar,
toolbarview > .bottom-bar.raised,
.toolbar-view .top-bar,
.toolbar-view .bottom-bar {
  --headerbar-bg-color:     ${container_high};
  --headerbar-fg-color:     ${on_surface};
  --headerbar-border-color: ${outline_variant};
  --headerbar-shade-color:  ${outline_variant};
}

/* Backdrop (unfocused window) variants */
headerbar:backdrop,
.titlebar:backdrop,
headerbar.titlebar:backdrop,
tabbar .box:backdrop,
searchbar > revealer > box:backdrop,
actionbar > revealer > box:backdrop,
toolbarview > .top-bar:backdrop,
toolbarview > .bottom-bar:backdrop {
  --headerbar-bg-color: ${container};
}

/* ── Explicit background override — use 'background' shorthand to reset ALL
 * background sub-properties. 'background: none' from libadwaita APPLICATION
 * CSS would win over 'background-color: x !important' in certain GTK4 cascade
 * edge cases, but 'background: x !important' beats it unambiguously.       */
headerbar,
.titlebar,
headerbar.titlebar,
.titlebar.horizontal,
adw-header-bar {
  background: ${container_low} !important;
  background-color: ${container_low} !important;
  background-image: none !important;
  border-image: none !important;
  color: ${on_surface} !important;
  border-bottom: 1px solid alpha(${outline_variant}, 0.5) !important;
  box-shadow: none !important;
}
headerbar:backdrop,
.titlebar:backdrop,
adw-header-bar:backdrop {
  background: ${container_low} !important;
  background-color: ${container_low} !important;
  background-image: none !important;
  border-image: none !important;
  color: ${on_surface_variant} !important;
  box-shadow: none !important;
}

/* tabbar — used in GNOME Web, Text Editor, etc. */
tabbar .box {
  background-color: ${container} !important;
  color: ${on_surface} !important;
  border-bottom: 1px solid ${outline_variant} !important;
}
tabbar .box:backdrop {
  background-color: ${container} !important;
}
tabbar tab {
  color: ${on_surface_variant} !important;
}
tabbar tab:checked {
  background-color: ${container_high} !important;
  color: ${on_surface} !important;
}
tabbar tab:hover {
  background-color: ${surface_bright} !important;
}

/* searchbar — used in Nautilus, Files, Text Editor etc. */
searchbar > revealer > box {
  background-color: ${container} !important;
  color: ${on_surface} !important;
  border-bottom: 1px solid ${outline_variant} !important;
}
searchbar > revealer > box:backdrop {
  background-color: ${container} !important;
}

/* actionbar — used in Nautilus selection mode, GNOME Photos etc. */
actionbar > revealer > box {
  background-color: ${container} !important;
  color: ${on_surface} !important;
  border-top: 1px solid ${outline_variant} !important;
}
actionbar > revealer > box:backdrop {
  background-color: ${container} !important;
}

/* toolbarview bars — the GNOME 45+ replacement for headerbar.
 * Use both direct-child (>) and descendant ( ) selectors to catch
 * Nautilus AdwToolbarView and any intermediate wrappers. */
toolbarview > .top-bar,
toolbarview > .top-bar.raised,
toolbarview .top-bar,
.top-bar {
  background: ${container} !important;
  color: ${on_surface} !important;
  border-bottom: 1px solid ${outline_variant} !important;
}
toolbarview > .top-bar:backdrop,
toolbarview > .top-bar.raised:backdrop,
toolbarview .top-bar:backdrop,
.top-bar:backdrop {
  background: ${container} !important;
  color: ${on_surface_variant} !important;
}
toolbarview > .bottom-bar,
toolbarview > .bottom-bar.raised,
toolbarview .bottom-bar,
.bottom-bar {
  background-color: ${container_high} !important;
  color: ${on_surface} !important;
  border-top: 1px solid ${outline_variant} !important;
}
.bottom-bar:backdrop {
  background-color: ${container} !important;
}

/* toolbar (GTK3) */
toolbar {
  background-color: ${container} !important;
  color: ${on_surface} !important;
  background-image: none !important;
  border-bottom: 1px solid ${outline_variant} !important;
}

headerbar .title,
.titlebar .title {
  color: @on_surface;
  font-weight: 600;
}
headerbar .subtitle,
.titlebar .subtitle {
  color: @on_surface_variant_color;
  font-size: smaller;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 6. SIDEBAR & NAVIGATION SIDEBAR
 * ════════════════════════════════════════════════════════════════════════════ */

.sidebar,
.navigation-sidebar,
placessidebar,
placessidebar list {
  background-color: @sidebar_bg_color;
  color: @sidebar_fg_color;
  border-right: 1px solid @borders;
}

placessidebar > viewport.frame {
  border: none;
}

.sidebar row,
.navigation-sidebar row,
placessidebar row {
  border-radius: 6px;
  margin: 1px 4px;
  padding: 2px 6px;
  color: @on_surface;
}

.sidebar row:hover,
.navigation-sidebar row:hover,
placessidebar row:hover {
  background-color: alpha(@accent_bg_color, 0.08);
}

.sidebar row:selected,
.navigation-sidebar row:selected,
placessidebar row:selected {
  background-color: alpha(@accent_bg_color, 0.18);
  color: @accent_bg_color;
}

.sidebar row:selected:focus,
.navigation-sidebar row:selected:focus,
placessidebar row:selected:focus {
  background-color: @primary_container_color;
  color: @on_primary_container_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 7. BUTTONS
 *    Tonal Material You button hierarchy:
 *    flat < regular (tonal) < suggested-action (primary) < destructive
 * ════════════════════════════════════════════════════════════════════════════ */

/* Base button — tonal surface */
button {
  background-color: ${container_high};
  color: ${on_surface};
  border: 1px solid ${outline_variant};
  border-radius: 6px;
  padding: 5px 12px;
  transition: background-color 120ms ease, box-shadow 120ms ease;
}
button:hover {
  background-color: ${surface_bright};
  box-shadow: 0 1px 4px alpha(${outline_variant}, 0.18);
}
button:active {
  background-color: ${primary_container};
  color: ${on_primary_container};
  border-color: transparent;
  box-shadow: none;
}
button:focus:focus-visible {
  outline: 2px solid ${primary};
  outline-offset: 2px;
}
button:disabled {
  opacity: 0.45;
}

/* Suggested action — primary filled */
button.suggested-action,
.suggested-action {
  background-color: ${primary};
  color: ${on_primary};
  border-color: transparent;
  font-weight: 600;
}
button.suggested-action:hover,
.suggested-action:hover {
  background-color: mix(${primary}, white, 0.08);
  box-shadow: 0 2px 6px alpha(${primary}, 0.35);
}
button.suggested-action:active,
.suggested-action:active {
  background-color: mix(${primary}, ${outline_variant}, 0.08);
  box-shadow: none;
}

/* Destructive action — error filled */
button.destructive-action,
.destructive-action {
  background-color: ${error};
  color: ${on_error};
  border-color: transparent;
  font-weight: 600;
}
button.destructive-action:hover {
  background-color: mix(${error}, white, 0.08);
  box-shadow: 0 2px 6px alpha(${error}, 0.35);
}
button.destructive-action:active {
  background-color: mix(${error}, ${outline_variant}, 0.08);
  box-shadow: none;
}

/* Flat / icon-only buttons */
button.flat,
button.image-button.flat,
button.circular {
  background-color: transparent;
  border-color: transparent;
  box-shadow: none;
}
button.flat:hover,
button.image-button.flat:hover,
button.circular:hover {
  background-color: alpha(${on_bg}, 0.08);
  border-color: transparent;
  box-shadow: none;
}
button.flat:active,
button.image-button.flat:active,
button.circular:active {
  background-color: alpha(${on_bg}, 0.14);
  border-color: transparent;
  box-shadow: none;
}

/* Toggle buttons (active/checked state) */
button:checked,
button.toggle:checked {
  background-color: ${secondary_container};
  color: ${on_secondary_container};
  border-color: transparent;
}
button:checked:hover,
button.toggle:checked:hover {
  background-color: mix(${secondary_container}, white, 0.08);
}

/* ════════════════════════════════════════════════════════════════════════════
 * 8. CHECKBOXES & RADIO BUTTONS
 * ════════════════════════════════════════════════════════════════════════════ */

checkbutton,
radiobutton {
  color: @on_surface;
  border-radius: 4px;
  padding: 2px 4px;
}
checkbutton:hover,
radiobutton:hover {
  background-color: alpha(@window_fg_color, 0.06);
}

check,
radio {
  background-color: transparent;
  border: 2px solid @outline_color;
  border-radius: 3px;
  min-width: 18px;
  min-height: 18px;
  transition: background-color 120ms ease, border-color 120ms ease;
}
radio { border-radius: 9px; }

check:checked,
check:indeterminate {
  background-color: @accent_bg_color;
  border-color: @accent_bg_color;
  color: @accent_fg_color;
}
radio:checked {
  background-color: @accent_bg_color;
  border-color: @accent_bg_color;
  color: @accent_fg_color;
}
check:disabled,
radio:disabled {
  opacity: 0.45;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 9. SWITCH / TOGGLE
 * ════════════════════════════════════════════════════════════════════════════ */

switch {
  background-color: @outline_color;
  color: @surface;
  border-radius: 14px;
  transition: background-color 200ms ease;
  min-width: 52px;
  min-height: 28px;
}
switch:hover {
  background-color: mix(white, @outline_color, 0.1);
}
switch:checked {
  background-color: @accent_bg_color;
}
switch:checked:hover {
  background-color: mix(white, @accent_bg_color, 0.1);
}
switch:disabled {
  opacity: 0.45;
}

switch slider {
  background-color: @surface;
  border-radius: 12px;
  margin: 3px;
  min-width: 22px;
  min-height: 22px;
  box-shadow: 0 1px 4px alpha(${outline_variant}, 0.3);
  transition: min-width 200ms ease, min-height 200ms ease,
              background-color 200ms ease;
}
switch:checked slider {
  background-color: @accent_fg_color;
  min-width: 26px;
  min-height: 26px;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 10. ENTRY / TEXT INPUT
 * ════════════════════════════════════════════════════════════════════════════ */

entry,
.entry,
scrolledwindow > entry,
viewport > entry {
  background-color: ${container_low} !important;
  color: ${on_surface};
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 6px;
  padding: 6px 10px;
  caret-color: ${primary};
  transition: border-color 150ms ease, box-shadow 150ms ease;
}
entry:focus-within,
.entry:focus-within,
scrolledwindow > entry:focus-within,
viewport > entry:focus-within {
  border-color: ${primary};
  box-shadow: 0 0 0 2px alpha(${primary}, 0.22);
  background-color: ${container_low} !important;
}
entry:disabled,
.entry:disabled {
  opacity: 0.45;
}

entry > image { color: ${on_surface_variant}; }
entry > image:hover { color: ${on_surface}; }

/* Placeholder */
entry > text > placeholder {
  color: ${on_surface_variant};
  font-style: italic;
  opacity: 0.6;
}

/* Search entry */
searchentry {
  background-color: ${container};
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 24px;
}
searchentry:focus-within {
  border-color: ${primary};
  box-shadow: 0 0 0 2px alpha(${primary}, 0.22);
  background-color: ${container};
}
searchentry > text,
searchentry text {
  background-color: transparent;
  color: ${on_surface};
}

/* Text view */
textview,
textview > text {
  background-color: ${surface};
  color: ${on_surface};
}
textview > text > selection,
entry > text > selection,
spinbutton > text > selection,
label selection,
searchentry > text > selection {
  background-color: ${primary};
  color: ${selection_fg};
}

/* SpinButton */
spinbutton {
  background-color: @surface_container_high;
  border: 1px solid @outline_variant_color;
  border-radius: 6px;
}
spinbutton:focus-within {
  border-color: @accent_bg_color;
  box-shadow: 0 0 0 2px alpha(@accent_bg_color, 0.22);
}
spinbutton > text {
  background-color: transparent;
  color: @on_surface;
}
spinbutton > button {
  background-color: transparent;
  border: none;
  border-radius: 0;
  box-shadow: none;
}
spinbutton > button:hover {
  background-color: alpha(@window_fg_color, 0.08);
}

/* Linked widgets (button groups) */
.linked > entry,
.linked > entry:focus-within {
  border-radius: 0;
}
.linked > entry:first-child  { border-radius: 6px 0 0 6px; }
.linked > entry:last-child   { border-radius: 0 6px 6px 0; }
.linked > entry:only-child   { border-radius: 6px; }

/* ════════════════════════════════════════════════════════════════════════════
 * 11. COMBOBOX / DROPDOWN
 * ════════════════════════════════════════════════════════════════════════════ */

combobox,
dropdown {
  background-color: @surface_container_high;
  color: @on_surface;
  border: 1px solid @outline_variant_color;
  border-radius: 6px;
}
combobox:focus-within,
dropdown:focus-within {
  border-color: @accent_bg_color;
  box-shadow: 0 0 0 2px alpha(@accent_bg_color, 0.22);
}
combobox > .linked > entry,
combobox > .linked > button {
  background-color: transparent;
  border: none;
  box-shadow: none;
  color: @on_surface;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 12. SCROLLBAR
 *     All rules use !important — WhiteSur GTK3 theme will otherwise win.
 *     GTK3 scrollbar node tree: scrollbar > contents > trough > slider
 *     GTK4 scrollbar node tree: scrollbar > trough > slider
 *     Both are covered via descendant selectors.
 * ════════════════════════════════════════════════════════════════════════════ */

/* Track background — whole scrollbar widget */
scrollbar,
scrollbar.vertical,
scrollbar.horizontal {
  background-color: ${container_low} !important;
  border: none !important;
}

/* GTK3 intermediate 'contents' node + trough */
scrollbar > contents,
scrollbar trough,
scrollbar > trough,
scrollbar > contents > trough {
  background-color: ${container_low} !important;
  border: none !important;
  border-radius: 100px !important;
}

/* Slider (thumb) */
scrollbar slider,
scrollbar trough > slider,
scrollbar > trough > slider,
scrollbar > contents > trough > slider {
  background-color: ${on_surface_variant} !important;
  border-radius: 100px !important;
  min-width: 6px !important;
  min-height: 6px !important;
  margin: 3px !important;
  transition: background-color 150ms ease, min-width 150ms ease,
              min-height 150ms ease;
}
scrollbar slider:hover,
scrollbar trough > slider:hover,
scrollbar > contents > trough > slider:hover {
  background-color: ${on_surface} !important;
  min-width: 8px !important;
  min-height: 8px !important;
  margin: 2px !important;
}
scrollbar slider:active,
scrollbar trough > slider:active,
scrollbar > contents > trough > slider:active {
  background-color: ${primary} !important;
  min-width: 8px !important;
  min-height: 8px !important;
  margin: 2px !important;
}

/* Arrow buttons (GTK3 scrollbars with arrows) */
scrollbar button,
scrollbar > button {
  background-color: ${container} !important;
  color: ${on_surface} !important;
  border: none !important;
  min-width: 14px !important;
  min-height: 14px !important;
}
scrollbar button:hover,
scrollbar > button:hover {
  background-color: ${container_high} !important;
}

/* Overlay scrollbars (GTK4 default) */
scrollbar.overlay-indicator {
  background-color: transparent !important;
}
scrollbar.overlay-indicator trough,
scrollbar.overlay-indicator > trough {
  background-color: transparent !important;
}
scrollbar.overlay-indicator trough > slider,
scrollbar.overlay-indicator > trough > slider {
  background-color: ${on_surface_variant} !important;
  box-shadow: 0 0 0 1px alpha(${outline_variant}, 0.2) !important;
  min-width: 6px !important;
  min-height: 6px !important;
}
scrollbar.overlay-indicator:not(.hovering):not(.dragging) {
  opacity: 0;
  transition: opacity 300ms ease;
}
scrollbar.overlay-indicator.hovering,
scrollbar.overlay-indicator.dragging {
  opacity: 1;
}

/* Scrollbar sizing */
scrollbar.vertical   slider { min-width: 6px !important; }
scrollbar.horizontal slider { min-height: 6px !important; }

/* ════════════════════════════════════════════════════════════════════════════
 * 13. PROGRESS BAR
 * ════════════════════════════════════════════════════════════════════════════ */

progressbar {
  color: @on_surface;
}
progressbar > trough {
  background-color: @surface_container_high;
  border-radius: 100px;
  min-height: 6px;
}
progressbar > trough > progress {
  background-color: @accent_bg_color;
  border-radius: 100px;
  min-height: 6px;
}
progressbar > trough > progress:indeterminate {
  background-image: linear-gradient(
    to right,
    transparent 0%,
    @accent_bg_color 30%,
    @accent_bg_color 70%,
    transparent 100%
  );
}
progressbar.osd > trough {
  background-color: alpha(@surface_container_highest, 0.6);
}
progressbar.osd > trough > progress {
  background-color: @accent_bg_color;
}

/* Level bar (e.g. storage usage) */
levelbar > trough {
  background-color: @surface_container_high;
  border-radius: 100px;
}
levelbar > trough > block.filled {
  background-color: @accent_bg_color;
  border-radius: 100px;
}
levelbar > trough > block.empty {
  background-color: transparent;
}
levelbar > trough > block.filled.high  { background-color: @success_color; }
levelbar > trough > block.filled.low   { background-color: @error_color; }

/* ════════════════════════════════════════════════════════════════════════════
 * 14. SCALE / SLIDER
 * ════════════════════════════════════════════════════════════════════════════ */

scale trough {
  background-color: @surface_container_high;
  border-radius: 100px;
  min-height: 4px;
  min-width: 4px;
}
scale trough > fill,
scale trough > highlight {
  background-color: @accent_bg_color;
  border-radius: 100px;
}
scale trough > slider {
  background-color: @accent_bg_color;
  border-radius: 100px;
  min-width: 18px;
  min-height: 18px;
  box-shadow: 0 1px 4px alpha(${outline_variant}, 0.28);
  transition: min-width 120ms ease, min-height 120ms ease;
}
scale trough > slider:hover {
  background-color: mix(white, @accent_bg_color, 0.1);
  min-width: 22px;
  min-height: 22px;
  box-shadow: 0 2px 6px alpha(@accent_bg_color, 0.4);
}
scale trough > slider:active {
  min-width: 20px;
  min-height: 20px;
}
scale:disabled trough {
  opacity: 0.45;
}
scale marks > mark > indicator {
  background-color: @outline_variant_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 15. NOTEBOOK / TABS
 * ════════════════════════════════════════════════════════════════════════════ */

notebook > header {
  background-color: @headerbar_bg_color;
  border-bottom: 1px solid @outline_variant_color;
  padding: 0 4px;
}
notebook > header.top    { border-bottom: 1px solid @outline_variant_color; }
notebook > header.bottom { border-top:    1px solid @outline_variant_color; }
notebook > header.left   { border-right:  1px solid @outline_variant_color; }
notebook > header.right  { border-left:   1px solid @outline_variant_color; }

notebook > header > tabs > tab {
  background-color: transparent;
  color: @on_surface_variant_color;
  padding: 8px 16px;
  border-radius: 0;
  border: none;
  border-bottom: 3px solid transparent;
  transition: color 150ms ease, border-color 150ms ease;
}
notebook > header > tabs > tab:hover {
  color: @on_surface;
  background-color: alpha(@window_fg_color, 0.06);
}
notebook > header > tabs > tab:checked {
  color: @accent_bg_color;
  border-bottom-color: @accent_bg_color;
  background-color: transparent;
  font-weight: 600;
}
notebook > header > tabs > tab button.flat {
  padding: 0;
  min-width: 20px;
  min-height: 20px;
  border-radius: 100px;
  color: @on_surface_variant_color;
}
notebook > header > tabs > tab button.flat:hover {
  background-color: alpha(@window_fg_color, 0.1);
  color: @on_surface;
}
notebook > stack {
  background-color: @view_bg_color;
  border: 1px solid @outline_variant_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 16. TREEVIEW / LISTVIEW / COLUMNVIEW
 * ════════════════════════════════════════════════════════════════════════════ */

treeview.view,
columnview,
listview {
  background-color: @view_bg_color;
  color: @on_surface;
}

/* Column headers — all treeview header button variants (GTK3 + GTK4) */
treeview header,
treeview > header,
treeview header button,
treeview > header > button,
treeview.view > header > button,
columnview > header,
columnview > header > row > button,
columnview > header button {
  background-color: ${container} !important;
  background-image: none !important;
  color: ${on_surface_variant} !important;
  border-bottom: 1px solid ${outline_variant} !important;
  border-right: 1px solid ${outline_variant} !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  font-weight: 600;
  font-size: smaller;
  padding: 6px 10px;
}
/* Nautilus: column sort header matches body background for flat consistency.
 * padding-left 6px aligns the label with list row content (rows have margin: 1px 4px). */
window.nautilus-window columnview > header,
window.nautilus-window columnview > header > row,
window.nautilus-window columnview > header > row > button,
window.nautilus-window columnview > header button {
  background-color: ${bg} !important;
  border-top: none !important;
  border-bottom: none !important;
  border-right: 1px solid alpha(${outline_variant}, 0.55) !important;
  border-left: none !important;
  box-shadow: none !important;
  padding: 5px 6px !important;
}
window.nautilus-window columnview > separator,
window.nautilus-window columnview separator {
  background-color: transparent !important;
  min-height: 0 !important;
  min-width: 0 !important;
  opacity: 0 !important;
}
window.nautilus-window columnview > listview {
  border-top: none !important;
}
treeview header button:hover,
treeview > header > button:hover,
treeview.view > header > button:hover,
columnview > header > row > button:hover,
columnview > header button:hover {
  background-color: ${surface_bright} !important;
  color: ${on_surface} !important;
}
treeview header button:active,
treeview > header > button:active,
treeview.view > header > button:active,
columnview > header > row > button:active,
columnview > header button:active {
  background-color: ${container_high} !important;
  color: ${primary} !important;
}

/* path-bar / pathbar — covers both GTK3 class (.path-bar) and GTK4 node (pathbar).
 * WhiteSur sets pathbar > button:checked { background-color: #b8b8b8 } (near-white)
 * which is the currently-active directory crumb — override it to our dark palette. */
path-bar,
path-bar > button,
path-bar > button.text-button,
path-bar > button.image-button,
pathbar,
pathbar > button,
pathbar > button.text-button,
pathbar > button.image-button {
  background-color: ${container} !important;
  background-image: none !important;
  border-image: none !important;
  color: ${on_surface} !important;
  box-shadow: none !important;
}
path-bar > button:hover,
pathbar > button:hover {
  background-color: ${container_high} !important;
}
path-bar > button:checked,
path-bar > button:active,
pathbar > button:checked,
pathbar > button:active {
  background-color: ${primary} !important;
  background-image: none !important;
  border-image: none !important;
  color: ${on_primary} !important;
  box-shadow: none !important;
}

/* Row states */
treeview.view:hover,
listview > row:hover,
columnview > listview > row:hover {
  background-color: alpha(@window_fg_color, 0.05);
}
treeview.view:selected,
listview > row:selected,
columnview > listview > row:selected {
  background-color: alpha(@accent_bg_color, 0.16);
  color: @on_surface;
}
treeview.view:selected:focus,
listview > row:selected:focus,
columnview > listview > row:selected:focus {
  background-color: @accent_bg_color;
  color: ${selection_fg};
}

/* Alternating row colors (subtle) */
treeview.view:nth-child(even) {
  background-color: alpha(@window_fg_color, 0.025);
}

/* Expanders */
treeview.view arrow {
  color: @on_surface_variant_color;
}
treeview.view arrow:hover {
  color: @on_surface;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 17. SELECTION
 * ════════════════════════════════════════════════════════════════════════════ */

:selected {
  background-color: @accent_bg_color;
  color: ${selection_fg};
}
/* Unfocused selection — tonal, less dominant */
:selected:not(:focus-within) {
  background-color: @secondary_container_color;
  color: @on_secondary_container_color;
}

row:selected {
  background-color: alpha(@accent_bg_color, 0.16);
  color: @on_surface;
}
row:selected:focus-within {
  background-color: @accent_bg_color;
  color: ${selection_fg};
}

/* ════════════════════════════════════════════════════════════════════════════
 * 18. POPOVERS & CONTEXT MENUS
 * ════════════════════════════════════════════════════════════════════════════ */

/* Popover / dropdown menu rendering.
 *
 * Box-shadow on popover > contents bleeds into the popup window's empty space,
 * which requires alpha channel transparency to avoid black bleed — unreliable.
 * Fix: give window.popup.csd the menu background + border so it fills completely.
 * No empty space → no black area, regardless of compositor alpha support.
 */
popover {
  background: none;
}
popover > arrow {
  /* arrow is invisible — the window background fills everything cleanly */
  background: transparent;
  border: none;
  -gtk-icon-shadow: none;
}
popover > contents,
popover.menu > contents {
  /* window.popup.csd provides background/border/radius — keep contents flat */
  background: transparent;
  color: @on_surface;
  border: none;
  border-radius: 0;
  padding: 4px;
  box-shadow: none;
}

/* GTK3 menus */
menu,
.menu,
.context-menu {
  background-color: @popover_bg_color;
  color: @on_surface;
  border: 1px solid @outline_variant_color;
  border-radius: 10px;
  padding: 4px;
  box-shadow: 0 10px 28px alpha(${outline_variant}, 0.12),
              0 2px   6px alpha(${primary}, 0.04);
}

menuitem {
  color: @on_surface;
  border-radius: 6px;
  padding: 6px 10px;
  min-height: 30px;
  transition: background-color 100ms ease;
}
menuitem:hover,
modelbutton:hover {
  background-color: alpha(@accent_bg_color, 0.30);
  color: ${selection_fg};
}
menuitem:active,
modelbutton:active {
  background-color: alpha(@accent_bg_color, 0.45);
  color: ${selection_fg};
}
menuitem:disabled {
  color: alpha(@on_surface, 0.45);
}
menuitem accelerator {
  color: @on_surface_variant_color;
}
menuitem check,
menuitem radio {
  background-color: transparent;
  border: none;
  min-width: 14px;
  min-height: 14px;
}
menuitem check:checked,
menuitem radio:checked {
  color: @accent_bg_color;
}

menu > arrow,
.menu > arrow {
  background-color: @popover_bg_color;
  color: @on_surface_variant_color;
  min-height: 16px;
}

/* Separator inside menus */
menu > separator,
.menu > separator,
menu separator,
.menu separator {
  background-color: @outline_variant_color;
  min-height: 1px;
  margin: 4px 8px;
}

/* Menu bar */
menubar {
  background-color: @headerbar_bg_color;
  color: @on_surface;
  padding: 0 4px;
}
menubar > item {
  padding: 4px 10px;
  border-radius: 6px;
  color: @on_surface;
}
menubar > item:hover {
  background-color: alpha(@window_fg_color, 0.08);
}
menubar > item:active,
menubar > item:checked {
  background-color: alpha(@accent_bg_color, 0.16);
  color: @accent_bg_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 19. TOOLTIP
 * ════════════════════════════════════════════════════════════════════════════ */

tooltip,
tooltip.background {
  background-color: @surface_bright_color;
  color: @on_surface;
  border: 1px solid @outline_variant_color;
  border-radius: 6px;
  padding: 4px 10px;
  box-shadow: 0 2px 8px alpha(${outline_variant}, 0.3);
}
tooltip > label {
  color: @on_surface;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 20. CARDS
 * ════════════════════════════════════════════════════════════════════════════ */

.card {
  background-color: @card_bg_color;
  color: @card_fg_color;
  border: 1px solid @outline_variant_color;
  border-radius: 10px;
  box-shadow: 0 1px 4px alpha(${outline_variant}, 0.2);
}
.card:hover {
  box-shadow: 0 2px 8px alpha(${outline_variant}, 0.28);
  border-color: @outline_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 21. DIALOGS
 * ════════════════════════════════════════════════════════════════════════════ */

dialog {
  background-color: @dialog_bg_color;
  color: @dialog_fg_color;
  border-radius: 14px;
}
dialog > box.dialog-vbox {
  background-color: @dialog_bg_color;
}
messagedialog {
  background-color: @dialog_bg_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 22. FRAME & SEPARATOR
 * ════════════════════════════════════════════════════════════════════════════ */

frame > border,
.frame {
  border: 1px solid @outline_variant_color;
  border-radius: 6px;
}
separator {
  background-color: transparent;
  min-width: 1px;
  min-height: 1px;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 23. INFO / STATUS BAR
 * ════════════════════════════════════════════════════════════════════════════ */

infobar {
  border-bottom: 1px solid @outline_variant_color;
}
infobar.info > revealer > box {
  background-color: @surface_container_high;
  color: @on_surface;
}
infobar.question > revealer > box {
  background-color: @primary_container_color;
  color: @on_primary_container_color;
}
infobar.warning > revealer > box {
  background-color: @warning_bg_color;
  color: @warning_fg_color;
}
infobar.error > revealer > box {
  background-color: @error_container_color;
  color: @on_error_container_color;
}

statusbar {
  background-color: @surface_container_low;
  color: @on_surface_variant_color;
  border-top: 1px solid @outline_variant_color;
  padding: 2px 8px;
  font-size: smaller;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 24. LINK
 * ════════════════════════════════════════════════════════════════════════════ */

link,
label.link {
  color: @accent_bg_color;
  text-decoration-color: alpha(@accent_bg_color, 0.4);
}
link:hover,
label.link:hover {
  color: mix(white, @accent_bg_color, 0.15);
}
link:visited,
label.link:visited {
  color: @visited_link_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 25. BADGE / PILL / TAG (GNOME 43+)
 * ════════════════════════════════════════════════════════════════════════════ */

.badge,
.tag {
  background-color: @secondary_container_color;
  color: @on_secondary_container_color;
  border-radius: 100px;
  padding: 2px 8px;
  font-size: smaller;
  font-weight: 600;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 26. EXPANDER
 * ════════════════════════════════════════════════════════════════════════════ */

expander > title {
  color: @on_surface;
  padding: 4px 0;
}
expander > title:hover {
  background-color: alpha(@window_fg_color, 0.06);
}
expander > title > arrow {
  color: @on_surface_variant_color;
  transition: transform 200ms ease;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 27. CALENDAR
 * ════════════════════════════════════════════════════════════════════════════ */

calendar {
  background-color: @view_bg_color;
  color: @on_surface;
  border: 1px solid @outline_variant_color;
  border-radius: 10px;
  padding: 8px;
}
calendar > header {
  background-color: @headerbar_bg_color;
  color: @on_surface;
  border-radius: 10px 10px 0 0;
  padding: 6px 8px;
}
calendar:selected,
calendar .highlight {
  background-color: @accent_bg_color;
  color: @accent_fg_color;
  border-radius: 100px;
  font-weight: 600;
}
calendar .today {
  color: @accent_bg_color;
  font-weight: 700;
}
calendar .other-month {
  color: alpha(@on_surface, 0.35);
}

/* ════════════════════════════════════════════════════════════════════════════
 * 28. OSD (on-screen display — volume/brightness overlays)
 * ════════════════════════════════════════════════════════════════════════════ */

.osd {
  background-color: alpha(@surface_bright_color, 0.92);
  color: @on_surface;
  border-radius: 14px;
  border: 1px solid @outline_variant_color;
  box-shadow: 0 4px 16px alpha(${outline_variant}, 0.4);
}

/* ════════════════════════════════════════════════════════════════════════════
 * 29. CSD WINDOW DECORATION
 * ════════════════════════════════════════════════════════════════════════════ */

window.csd {
  outline-color: transparent;
  box-shadow: 0 8px 40px alpha(${outline_variant}, 0.5),
              0 2px  6px alpha(${outline_variant}, 0.3);
}
window.csd:backdrop {
  box-shadow: 0 4px 20px alpha(${outline_variant}, 0.3),
              0 1px  3px alpha(${outline_variant}, 0.2);
}
window.popup.csd {
  /* Fill the entire popup window with the menu background so there is no
   * empty space that could appear black. Border + radius here instead of
   * on popover > contents, removing any dependency on alpha transparency. */
  background-color: ${container_highest};
  background-image: none;
  border: 1.5px solid alpha(${outline_variant}, 0.65);
  border-radius: 10px;
  box-shadow: none;
  outline: none;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 30. ADDITIONAL SCAFFOLD SAFETY NETS
 *     Catch any remaining transparent-by-default containers.
 * ════════════════════════════════════════════════════════════════════════════ */

/* navigationview inner stack */
navigationview > stack {
  background-color: ${bg} !important;
  background-image: none !important;
}
/* scrolled window viewport */
scrolledwindow > viewport {
  background-color: ${surface} !important;
  background-image: none !important;
}
/* adw-bin and generic overlay containers */
adw-bin,
.overlay > widget,
overlay > widget {
  background-color: transparent;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 31. APP-SPECIFIC OVERRIDES
 * ════════════════════════════════════════════════════════════════════════════ */

/* Nautilus */
/* WhiteSur sets the Nautilus headerbar to transparent + a gradient background-image.
 * Override with the exact same ${bg} used for the body — zero colour difference. */
window.nautilus-window headerbar,
window.nautilus-window headerbar:backdrop,
.nautilus-window headerbar,
.nautilus-window headerbar:backdrop,
.nautilus-window.background.csd headerbar,
.nautilus-window.background.csd headerbar:backdrop {
  background-color: ${bg} !important;
  background-image: none !important;
  border-image: none !important;
  border-bottom: 1px solid alpha(${outline_variant}, 0.5) !important;
}
window.nautilus-window toolbarview > .top-bar,
window.nautilus-window toolbarview > .top-bar.raised,
window.nautilus-window toolbarview .top-bar,
window.nautilus-window .top-bar {
  background: ${bg} !important;
  background-color: ${bg} !important;
  background-image: none !important;
  border-image: none !important;
  color: ${on_surface} !important;
  border-bottom: none !important;
  box-shadow: none !important;
}
window.nautilus-window toolbarview,
window.nautilus-window navigationsplitview,
window.nautilus-window navigationsplitview > .content-bin {
  background-color: ${bg} !important;
  background-image: none !important;
}
window.nautilus-window scrolledwindow,
window.nautilus-window scrolledwindow > viewport {
  background-color: ${bg} !important;
  background-image: none !important;
  border: none !important;
  box-shadow: none !important;
}
window.nautilus-window listview,
window.nautilus-window gridview,
window.nautilus-window .view,
window.nautilus-window .content-view {
  background-color: ${bg} !important;
  color: ${on_surface} !important;
}
window.nautilus-window .navigation-sidebar,
window.nautilus-window navigationsplitview > .sidebar-bin {
  background-color: ${bg} !important;
  color: ${on_surface} !important;
  border-right: 2px solid alpha(${outline_variant}, 0.28) !important;
  box-shadow: 3px 0 14px -4px alpha(${outline_variant}, 0.35) !important;
}
window.nautilus-window row:selected {
  background-color: ${primary} !important;
  color: ${selection_fg} !important;
}
window.nautilus-window row:selected:not(:focus-within) {
  background-color: alpha(@accent_bg_color, 0.16) !important;
  color: @on_surface !important;
}
/* Subtle row dividers in Nautilus list view */
window.nautilus-window listview > row {
  border-bottom: 1px solid alpha(${outline_variant}, 0.08) !important;
}

/* Floating bar (Nautilus status / selection bar) */
.floating-bar {
  background-color: @surface_bright_color;
  border: 1px solid @outline_variant_color;
  border-radius: 100px;
  box-shadow: 0 2px 10px alpha(${outline_variant}, 0.3);
}

/* GNOME Software / generic libadwaita */
.application-window toolbarview,
.application-window navigationview > stack {
  background-color: @window_bg_color !important;
  background-image: none !important;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 32. MISCELLANEOUS POLISH
 * ════════════════════════════════════════════════════════════════════════════ */

/* Reduce libadwaita's white-highlight border on headerbars */
:root { --border-opacity: 6%; }

/* Spinner */
spinner { color: @accent_bg_color; }

/* Image widget */
image { color: @on_surface; }

/* Paned separator — 2px with top/bottom fade */
paned > separator {
  background-color: transparent;
  min-width: 2px;
  min-height: 2px;
}
paned.horizontal > separator {
  background-image: linear-gradient(to bottom,
    transparent 0%,
    alpha(${outline_variant}, 0.55) 20%,
    alpha(${outline_variant}, 0.55) 80%,
    transparent 100%);
}
paned.vertical > separator {
  background-image: linear-gradient(to right,
    transparent 0%,
    alpha(${outline_variant}, 0.55) 20%,
    alpha(${outline_variant}, 0.55) 80%,
    transparent 100%);
}

/* Group box label */
.groupbox label {
  color: @on_surface_variant_color;
  font-weight: 600;
  font-size: smaller;
}

/* Color swatch (e.g. color picker) */
colorchooser swatch,
.color-button {
  border: 2px solid @outline_variant_color;
  border-radius: 4px;
}
colorchooser swatch:selected {
  border-color: @accent_bg_color;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 33. UNIVERSAL GTK3/GTK4 COMPREHENSIVE OVERRIDES
 *     General selectors that work for ANY app without being app-specific.
 *     Covers file managers, text editors, browsers, and all GTK apps.
 * ════════════════════════════════════════════════════════════════════════════ */

/* ── Window containers ─────────────────────────────────────────────────── */
window,
window.background,
.background,
dialog,
messagedialog {
  background-color: ${bg} !important;
  color: ${on_bg} !important;
}

/* ── All paned/box containers — transparent so parent bg shows through ─── */
paned,
box {
  background-color: transparent;
}

/* ── Path/location bars (filechooser, file managers) ────────────────────── */
.path-bar,
.path-bar button,
.location-bar,
.location-entry,
.breadcrumb {
  background-color: ${container} !important;
  color: ${on_surface} !important;
}

/* ── Sidebars (universal — matches any sidebar regardless of app) ────────── */
.sidebar,
.navigation-sidebar,
placessidebar,
placessidebar list,
placessidebar > viewport,
.sidebar-pane,
.sidebar-panel,
.sidebar > viewport,
.sidebar > scrolledwindow > viewport,
navigationsplitview > .sidebar-bin {
  background-color: ${bg} !important;
  color: ${on_surface} !important;
}

/* ── Universal content views — works for any GTK3 list/icon widget ───────
 * These are listed from most specific to most general to avoid breaking
 * widgets that need different colors. */
treeview,
treeview.view,
iconview,
iconview > cell,
columnview,
listview,
layout,
fixed {
  background-color: ${surface} !important;
  color: ${on_surface} !important;
  background-image: none !important;
}

/* ── Content area selection states ──────────────────────────────────────── */
treeview:selected,
treeview > row:selected,
iconview:selected,
iconview > cell:selected,
layout:selected,
listview > row:selected {
  background-color: ${primary} !important;
  color: ${on_primary} !important;
}

/* ── Nemo-specific CSS nodes (registered via gtk_widget_class_set_css_name) ─
 * nemo-places-sidebar ≠ placessidebar — different CSS node names. */
nemo-places-sidebar,
nemo-places-sidebar list,
nemo-places-sidebar > scrolledwindow,
nemo-places-sidebar > scrolledwindow > *,
places-treeview {
  background-color: ${container_low} !important;
  color: ${on_surface} !important;
  background-image: none !important;
}

/* ── Toolbars (universal, any GTK3/GTK4 toolbar) ────────────────────────── */
toolbar,
toolbar.primary-toolbar,
.toolbar,
GtkToolbar {
  background-color: ${container_high} !important;
  color: ${on_surface} !important;
  background-image: none !important;
  border-image: none !important;
  border-bottom: 1px solid ${outline_variant} !important;
  box-shadow: none !important;
}
/* Toolbar children — buttons, entries, separators inside toolbar */
toolbar button,
toolbar > toolbutton,
toolbar > button,
.toolbar button {
  background-color: transparent !important;
  color: ${on_surface} !important;
  border: none !important;
  box-shadow: none !important;
}
toolbar button:hover,
.toolbar button:hover {
  background-color: alpha(white, 0.08) !important;
}

/* ── Menubars (universal) ────────────────────────────────────────────────── */
menubar {
  background-color: ${container_high} !important;
  color: ${on_surface} !important;
  background-image: none !important;
}

/* ── Status bars (universal) ─────────────────────────────────────────────── */
statusbar,
.statusbar {
  background-color: ${container_low} !important;
  color: ${on_surface_variant} !important;
  border-top: 1px solid ${outline_variant} !important;
}

/* ── Labels (ensure proper color inheritance) ───────────────────────────── */
label {
  color: ${on_surface};
}

/* ── Text in any text widget ─────────────────────────────────────────────── */
text,
richtext {
  background-color: ${surface} !important;
  color: ${on_surface} !important;
}

/* ── .content-pane: libadwaita's content region in AdwNavigationSplitView ───
 * WhiteSur sets .content-pane toolbarview { background: transparent } at THEME
 * level so the toolbarview is transparent and the content-pane bg shows
 * through. We must color .content-pane itself so headerbars inside it don't
 * fall through to the Adwaita grey that libadwaita bakes in. */
.content-pane {
  background-color: ${bg} !important;
  color: ${on_bg} !important;
}
.content-pane toolbarview,
.content-pane toolbarview.view {
  background-color: ${bg} !important;
}

/* ════════════════════════════════════════════════════════════════════════════
 * 34. @media (prefers-color-scheme: dark) — MATCH LIBADWAITA'S INJECTION LAYER
 *
 *     libadwaita 1.8 injects its dark @define-color tokens inside a
 *     @media (prefers-color-scheme: dark) block at APPLICATION priority (600).
 *     Our global @define-color declarations (USER, 800) should win by cascade
 *     priority, but we also inject inside the same media block so the
 *     specificity context is identical and there is zero ambiguity.
 *
 *     Additionally, we override the CSS custom properties inside this block
 *     so that var(--headerbar-bg-color) etc. resolve to OUR colors for every
 *     libadwaita app regardless of which method the app uses to read them.
 * ════════════════════════════════════════════════════════════════════════════ */
@media (prefers-color-scheme: dark) {
  /* Named color re-declarations in the dark-mode context */
  @define-color window_bg_color        ${bg};
  @define-color window_fg_color        ${on_bg};
  @define-color view_bg_color          ${surface};
  @define-color view_fg_color          ${on_surface};
  @define-color headerbar_bg_color     ${container_high};
  @define-color headerbar_fg_color     ${on_surface};
  @define-color headerbar_border_color ${outline_variant};
  @define-color headerbar_backdrop_color ${container};
  @define-color headerbar_shade_color  ${outline_variant};
  @define-color headerbar_darker_shade_color ${container_low};
  @define-color sidebar_bg_color       ${container_low};
  @define-color sidebar_fg_color       ${on_surface};
  @define-color sidebar_backdrop_color ${bg};
  @define-color card_bg_color          ${container};
  @define-color card_fg_color          ${on_surface};
  @define-color dialog_bg_color        ${container_high};
  @define-color dialog_fg_color        ${on_surface};
  @define-color popover_bg_color       ${container_highest};
  @define-color popover_fg_color       ${on_surface};

  /* CSS custom property re-declarations — these beat APPLICATION-level :root */
  :root {
    --window-bg-color:       ${bg};
    --window-fg-color:       ${on_bg};
    --view-bg-color:         ${surface};
    --view-fg-color:         ${on_surface};
    --headerbar-bg-color:    ${container_high};
    --headerbar-fg-color:    ${on_surface};
    --headerbar-border-color:${outline_variant};
    --headerbar-backdrop-color:${container};
    --headerbar-shade-color: ${outline_variant};
    --sidebar-bg-color:      ${container_low};
    --sidebar-fg-color:      ${on_surface};
    --sidebar-backdrop-color:${bg};
    --card-bg-color:         ${container};
    --dialog-bg-color:       ${container_high};
    --popover-bg-color:      ${container_highest};
  }

  /* Force headerbar background using the 'background' shorthand so ALL
   * background sub-properties are reset — not just background-color.
   * This catches any case where a 'background: none' from libadwaita's
   * compiled APPLICATION-level CSS is winning over our background-color. */
  headerbar,
  .titlebar,
  adw-header-bar,
  toolbarview > .top-bar,
  toolbarview > .top-bar.raised,
  toolbarview .top-bar,
  .top-bar {
    background: ${container_high} !important;
    color: ${on_surface} !important;
  }
  headerbar:backdrop,
  .titlebar:backdrop,
  adw-header-bar:backdrop,
  toolbarview > .top-bar:backdrop,
  .top-bar:backdrop {
    background: ${container_low} !important;
    color: ${on_surface_variant} !important;
  }

  /* Content pane in dark media context */
  .content-pane {
    background-color: ${bg} !important;
  }
  .content-pane toolbarview {
    background-color: ${bg} !important;
  }
}

/* ════════════════════════════════════════════════════════════════════════════
 * MATERIA COMPATIBILITY — override hardcoded #8ab4f8 blue accent
 * Materia bakes its blue accent directly into keyframes and element rules.
 * These rules replace every occurrence with the system primary colour.
 * ════════════════════════════════════════════════════════════════════════════ */

/* Ripple animations — redefine keyframes to use system primary */
@keyframes ripple {
  to { background-image: radial-gradient(circle, ${primary} 0%, transparent 0%); }
}
@keyframes ripple-on-slider {
  to { background-image: radial-gradient(farthest-side, ${primary} 100%, transparent 100%); }
}
@keyframes ripple-on-headerbar {
  from { background-image: radial-gradient(farthest-side, ${primary} 0%, transparent 0%); }
  to   { background-image: radial-gradient(farthest-side, ${primary} 100%, transparent 100%); }
}

/* Caret / insertion cursor */
entry, text, textview > text, searchentry, spinbutton {
  caret-color: ${primary};
}

/* Selection highlight — fully opaque so it's readable on any background */
selection {
  background-color: ${primary};
  color: ${on_primary};
}
/* Entry / search selection — explicit to prevent libadwaita overriding colour */
entry text selection,
entry > text > selection,
searchentry text selection,
searchentry > text > selection,
text selection {
  background-color: ${primary};
  color: ${on_primary};
}

/* Selection-mode titlebar (Materia sets background to #8ab4f8) */
.titlebar.selection-mode {
  background-color: ${primary};
  color: ${on_primary};
}
.titlebar.selection-mode button { color: ${on_primary}; }

/* Suggested-action — Materia hardcodes #8ab4f8 */
button.suggested-action,
.suggested-action > button {
  background-color: ${primary};
  color: ${on_primary};
}

/* Nautilus/headerbar controls — stop libadwaita/Materia blue-gray fallbacks */
headerbar,
.titlebar,
toolbarview > .top-bar,
window.nautilus-window headerbar,
window.nautilus-window .top-bar,
window.nautilus-window .path-bar-box,
window.nautilus-window .location-bar,
window.nautilus-window .nautilus-path-bar {
  text-shadow: none !important;
  -gtk-icon-shadow: none !important;
  box-shadow: none !important;
}
headerbar separator,
.titlebar separator,
toolbarview > .top-bar separator,
window.nautilus-window headerbar separator,
window.nautilus-window .top-bar separator,
window.nautilus-window .linked separator,
window.nautilus-window pathbar separator,
window.nautilus-window .path-bar-box separator {
  background-color: alpha(${outline_variant}, 0.45) !important;
  color: alpha(${outline_variant}, 0.45) !important;
  box-shadow: none !important;
}
headerbar button,
headerbar button.flat,
headerbar menubutton > button,
headerbar splitbutton > button,
.titlebar button,
.titlebar button.flat,
.titlebar menubutton > button,
.titlebar splitbutton > button,
toolbarview > .top-bar button,
toolbarview > .top-bar menubutton > button,
toolbarview > .top-bar splitbutton > button,
window.nautilus-window headerbar button,
window.nautilus-window .top-bar button {
  background-color: ${container} !important;
  background-image: none !important;
  border: 1.5px solid alpha(${outline_variant}, 0.75) !important;
  border-radius: 8px !important;
  color: ${on_surface} !important;
  box-shadow: inset 0 1px 0 alpha(${on_surface}, 0.06),
              0 1px 3px alpha(${outline_variant}, 0.18) !important;
}
headerbar button:hover,
headerbar button.flat:hover,
.titlebar button:hover,
.titlebar button.flat:hover,
toolbarview > .top-bar button:hover,
window.nautilus-window headerbar button:hover,
window.nautilus-window .top-bar button:hover {
  background-color: ${surface_bright} !important;
  color: ${on_surface} !important;
}
headerbar button:active,
headerbar button:checked,
.titlebar button:active,
.titlebar button:checked,
toolbarview > .top-bar button:active,
toolbarview > .top-bar button:checked,
window.nautilus-window headerbar button:active,
window.nautilus-window headerbar button:checked,
window.nautilus-window .top-bar button:active,
window.nautilus-window .top-bar button:checked {
  background-color: ${primary_container} !important;
  border-color: ${primary_container} !important;
  color: ${on_primary_container} !important;
}

/* Directory / location bar — blend with headerbar, soft border */
.location-bar,
.path-bar-box,
.nautilus-path-bar,
pathbar,
pathbar.linked,
headerbar .linked,
.titlebar .linked,
toolbarview > .top-bar .linked,
window.nautilus-window .location-bar,
window.nautilus-window .path-bar-box,
window.nautilus-window .nautilus-path-bar,
window.nautilus-window pathbar {
  background-color: ${container} !important;
  background-image: none !important;
  border-color: alpha(${outline_variant}, 0.45) !important;
  color: ${on_surface} !important;
  box-shadow: none !important;
  outline: none !important;
}
.location-bar entry,
.location-bar entry.flat,
.path-bar-box entry,
.path-bar-box entry.flat,
.nautilus-path-bar entry,
.nautilus-path-bar entry.flat,
headerbar entry,
headerbar entry.flat,
headerbar .linked > entry,
.titlebar entry,
.titlebar entry.flat,
.titlebar .linked > entry,
toolbarview > .top-bar entry,
toolbarview > .top-bar entry.flat,
toolbarview > .top-bar .linked > entry,
window.nautilus-window headerbar entry,
window.nautilus-window headerbar entry.flat,
window.nautilus-window headerbar .linked > entry,
window.nautilus-window .top-bar entry,
window.nautilus-window .top-bar entry.flat,
window.nautilus-window .top-bar .linked > entry,
window.nautilus-window .location-bar entry,
window.nautilus-window .location-bar entry.flat {
  background-color: ${container} !important;
  background-image: none !important;
  border: 1px solid alpha(${outline_variant}, 0.38) !important;
  outline: none !important;
  outline-color: transparent !important;
  color: ${on_surface} !important;
  box-shadow: none !important;
}
.location-bar entry:focus-within,
.location-bar entry.flat:focus-within,
.path-bar-box entry:focus-within,
.path-bar-box entry.flat:focus-within,
.nautilus-path-bar entry:focus-within,
.nautilus-path-bar entry.flat:focus-within,
headerbar entry:focus-within,
headerbar entry.flat:focus-within,
headerbar .linked > entry:focus-within,
.titlebar entry:focus-within,
.titlebar entry.flat:focus-within,
.titlebar .linked > entry:focus-within,
toolbarview > .top-bar entry:focus-within,
toolbarview > .top-bar entry.flat:focus-within,
toolbarview > .top-bar .linked > entry:focus-within,
window.nautilus-window headerbar entry:focus-within,
window.nautilus-window headerbar entry.flat:focus-within,
window.nautilus-window headerbar .linked > entry:focus-within,
window.nautilus-window .top-bar entry:focus-within,
window.nautilus-window .top-bar entry.flat:focus-within,
window.nautilus-window .top-bar .linked > entry:focus-within,
window.nautilus-window .location-bar entry:focus-within,
window.nautilus-window .location-bar entry.flat:focus-within {
  background-color: ${container} !important;
  border: 1px solid ${primary_container} !important;
  outline: none !important;
  outline-color: transparent !important;
  box-shadow: 0 0 0 1px alpha(${primary}, 0.18) !important;
}
.location-bar entry > text,
.path-bar-box entry > text,
.nautilus-path-bar entry > text,
headerbar entry > text,
.titlebar entry > text,
toolbarview > .top-bar entry > text,
window.nautilus-window headerbar entry > text,
window.nautilus-window .top-bar entry > text,
window.nautilus-window .location-bar entry > text {
  color: ${on_surface} !important;
}
.location-bar entry image,
.path-bar-box entry image,
.nautilus-path-bar entry image,
headerbar entry image,
.titlebar entry image,
toolbarview > .top-bar entry image,
window.nautilus-window headerbar entry image,
window.nautilus-window .top-bar entry image,
window.nautilus-window .location-bar entry image {
  color: ${on_surface_variant} !important;
  -gtk-icon-shadow: none !important;
}
.location-bar,
.path-bar-box,
.nautilus-path-bar,
pathbar,
window.nautilus-window .location-bar,
window.nautilus-window .path-bar-box,
window.nautilus-window .nautilus-path-bar,
window.nautilus-window pathbar,
headerbar .linked,
.titlebar .linked,
toolbarview > .top-bar .linked {
  box-shadow: none !important;
  outline: none !important;
  border-color: transparent !important;
}
window.nautilus-window headerbar *,
window.nautilus-window .top-bar *,
window.nautilus-window .location-bar *,
window.nautilus-window .path-bar-box *,
window.nautilus-window .nautilus-path-bar * {
  text-shadow: none !important;
  -gtk-icon-shadow: none !important;
}

/* Path-bar breadcrumb buttons — flat, no hard outline */
.path-bar-box .nautilus-path-bar button,
.titlebar .path-bar button,
pathbar.linked > button,
window.nautilus-window pathbar > button,
window.nautilus-window .nautilus-path-bar button {
  background-color: transparent;
  border-color: transparent;
  box-shadow: none;
  color: ${on_surface};
}
.path-bar-box .nautilus-path-bar button:hover,
.titlebar .path-bar button:hover,
pathbar.linked > button:hover,
window.nautilus-window pathbar > button:hover,
window.nautilus-window .nautilus-path-bar button:hover {
  background-color: alpha(${on_surface}, 0.08);
}
.path-bar-box .nautilus-path-bar button:checked,
.titlebar .path-bar button:checked,
pathbar.linked > button:checked,
window.nautilus-window pathbar > button:checked,
window.nautilus-window .nautilus-path-bar button:checked {
  background-color: alpha(${primary}, 0.18);
  color: ${primary};
}

/* ════════════════════════════════════════════════════════════════════════════
 * SCROLL EDGE — replace near-black shade with warm background-tinted fade
 * libadwaita drives undershoot/overshoot via --shade-color (near-black).
 * Materia's overshoot uses rgba(138,180,248,0.24) (blue). Both replaced here.
 * ════════════════════════════════════════════════════════════════════════════ */

/* Override libadwaita's --shade-color so undershoot shadows are warm */
* { --shade-color: alpha(${outline_variant}, 0.3); }

/* Overshoot indicators — transparent with subtle warm primary tint */
overshoot.top,
scrolledwindow > overshoot.top {
  background-color: transparent;
  background-image: radial-gradient(farthest-side at top, alpha(${primary}, 0.12) 0%, transparent 100%);
  box-shadow: none;
}
overshoot.bottom,
scrolledwindow > overshoot.bottom {
  background-color: transparent;
  background-image: radial-gradient(farthest-side at bottom, alpha(${primary}, 0.12) 0%, transparent 100%);
  box-shadow: none;
}
overshoot.left,
scrolledwindow > overshoot.left {
  background-color: transparent;
  background-image: radial-gradient(farthest-side at left, alpha(${primary}, 0.12) 0%, transparent 100%);
  box-shadow: none;
}
overshoot.right,
scrolledwindow > overshoot.right {
  background-color: transparent;
  background-image: radial-gradient(farthest-side at right, alpha(${primary}, 0.12) 0%, transparent 100%);
  box-shadow: none;
}

/* Undershoot shadows — warm fade instead of near-black */
undershoot.top,
scrolledwindow > undershoot.top {
  background-color: transparent;
  background-image: linear-gradient(to bottom, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}
undershoot.bottom,
scrolledwindow > undershoot.bottom {
  background-color: transparent;
  background-image: linear-gradient(to top, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}
undershoot.left,
scrolledwindow > undershoot.left {
  background-color: transparent;
  background-image: linear-gradient(to right, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}
undershoot.right,
scrolledwindow > undershoot.right {
  background-color: transparent;
  background-image: linear-gradient(to left, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}

CSS
)

# ── Geometry CSS (unchanged — spacing/radius are already good) ────────────────
geometry_css=$(cat <<'CSS'
/*
 * Quickshell GTK geometry tuning
 */

:root {
  --qs-pad-1: 4px;
  --qs-pad-2: 6px;
  --qs-pad-3: 8px;
  --qs-pad-4: 10px;
  --qs-radius-control: 6px;
  --qs-radius-list: 8px;
  --qs-radius-window: 12px;
  --qs-radius-menu: 10px;
  --qs-radius-popover: 12px;
}

window.csd,
window.csd.background,
dialog.background,
messagedialog.background {
  border-radius: var(--qs-radius-window);
}

headerbar,
.titlebar {
  min-height: 44px;
  padding: var(--qs-pad-1) var(--qs-pad-3);
}

button,
modelbutton,
menubutton > button,
splitbutton > button,
entry,
spinbutton,
combobox,
dropdown {
  min-height: 30px;
  padding: var(--qs-pad-2) var(--qs-pad-4);
  border-radius: var(--qs-radius-control);
}

list row,
listview row,
columnview row,
sidebar row,
navigation-sidebar row {
  margin: 1px 4px;
  border-radius: var(--qs-radius-list);
}

menu,
.menu {
  padding: var(--qs-pad-2);
  border-radius: var(--qs-radius-menu);
}

menuitem {
  min-height: 30px;
  padding: var(--qs-pad-2) var(--qs-pad-3);
  border-radius: var(--qs-radius-control);
}

popover > contents {
  border-radius: 0;
}

notebook > stack,
frame,
.card {
  border-radius: var(--qs-radius-list);
}

/* Motion */
button,
modelbutton,
menubutton > button,
splitbutton > button {
  transition: background-color 120ms cubic-bezier(0.4, 0, 0.2, 1),
              box-shadow       120ms cubic-bezier(0.4, 0, 0.2, 1),
              color            120ms cubic-bezier(0.4, 0, 0.2, 1);
}
entry,
spinbutton {
  transition: border-color 150ms cubic-bezier(0.4, 0, 0.2, 1),
              box-shadow   150ms cubic-bezier(0.4, 0, 0.2, 1);
}

CSS
)

# ── GTK3-safe CSS ─────────────────────────────────────────────────────────────
# GTK3 rejects CSS custom properties (--var), :root, var(), @media prefers-color-scheme.
# This separate heredoc uses only GTK3-compatible syntax:
#   • @define-color tokens (override named colors globally — fixes Nemo, Thunar)
#   • Simple selectors without :root / var() / :focus-within
#   • Hex / alpha() color values only
gtk3_colors_css=$(cat <<GTK3CSS
/*
 * Material You GTK3 color bridge — GTK3-safe, no !important.
 * User CSS priority (800) > theme CSS priority (200) so we win without it.
 * Generated from: $COLORS_JSON
 */

/* ══════════════════════════════════════════════════════════════
 * 1. @define-color TOKENS
 *    These override named colors globally — every GTK3 widget that
 *    reads @bg_color, @base_color, @selected_bg_color etc. gets our
 *    Material You colors automatically, including NemoIconContainer.
 * ══════════════════════════════════════════════════════════════ */
@define-color theme_fg_color            ${on_bg};
@define-color theme_bg_color            ${bg};
@define-color theme_base_color          ${surface};
@define-color theme_text_color          ${on_surface};
@define-color theme_selected_bg_color   ${primary};
@define-color theme_selected_fg_color   ${on_primary};
@define-color theme_unfocused_fg_color  ${on_bg};
@define-color theme_unfocused_bg_color  ${bg};
@define-color theme_unfocused_base_color ${surface};
@define-color theme_unfocused_text_color ${on_surface};
@define-color theme_unfocused_selected_bg_color  ${container};
@define-color theme_unfocused_selected_fg_color  ${on_surface};
@define-color fg_color                  ${on_bg};
@define-color bg_color                  ${bg};
@define-color base_color                ${surface};
@define-color text_color                ${on_surface};
@define-color selected_bg_color         ${primary};
@define-color selected_fg_color         ${on_primary};
@define-color insensitive_bg_color      ${container_low};
@define-color insensitive_fg_color      ${on_surface_variant};
@define-color insensitive_base_color    ${surface};
@define-color unfocused_insensitive_color ${on_surface_variant};
@define-color borders                   ${outline_variant};
@define-color unfocused_borders         ${outline_variant};
@define-color link_color                ${primary};
@define-color placeholder_text_color    ${on_surface_variant};
@define-color content_view_bg           ${surface};
@define-color text_view_bg              ${surface};
@define-color wm_bg                     ${container_high};
@define-color wm_bg_unfocused           ${container};

@define-color accent_color              ${primary};
@define-color accent_bg_color           ${primary};
@define-color accent_fg_color           ${on_primary};
@define-color destructive_color         ${error};
@define-color destructive_bg_color      ${error};
@define-color destructive_fg_color      ${on_error};
@define-color success_color             ${success_color};
@define-color warning_color             ${warning_color};
@define-color error_color               ${error};

@define-color window_bg_color           ${bg};
@define-color window_fg_color           ${on_bg};
@define-color view_bg_color             ${surface};
@define-color view_fg_color             ${on_surface};
@define-color headerbar_bg_color        ${container_high};
@define-color headerbar_fg_color        ${on_surface};
@define-color headerbar_border_color    ${outline_variant};
@define-color headerbar_backdrop_color  ${container};
@define-color headerbar_shade_color     ${outline_variant};
@define-color sidebar_bg_color          ${container_low};
@define-color sidebar_fg_color          ${on_surface};
@define-color card_bg_color             ${container};
@define-color card_fg_color             ${on_surface};
@define-color popover_bg_color          ${container_highest};
@define-color popover_fg_color          ${on_surface};
@define-color thumbnail_bg_color        ${container};
@define-color thumbnail_fg_color        ${on_surface};

@define-color primary_color              ${primary};
@define-color on_primary_color           ${on_primary};
@define-color primary_container_color    ${primary_container};
@define-color on_primary_container_color ${on_primary_container};
@define-color secondary_color            ${secondary};
@define-color on_secondary_color         ${on_secondary};
@define-color secondary_container_color  ${secondary_container};
@define-color on_secondary_container_color ${on_secondary_container};
@define-color outline_color              ${outline};
@define-color outline_variant_color      ${outline_variant};
@define-color on_surface                 ${on_surface};
@define-color on_surface_variant         ${on_surface_variant};
@define-color surface_bright             ${surface_bright};
@define-color surface_container_lowest  ${container_lowest};
@define-color surface_container_low     ${container_low};
@define-color surface_container         ${container};
@define-color surface_container_high    ${container_high};
@define-color surface_container_highest ${container_highest};

/* ══════════════════════════════════════════════════════════════
 * 2. WINDOW & BACKGROUND
 * ══════════════════════════════════════════════════════════════ */
window,
window.background,
.background,
dialog {
  background-color: ${bg};
  color: ${on_bg};
}

/* GTK3 containers don't inherit background — set them explicitly so nothing
 * falls through to the theme's default grey. Specific widgets override below. */
window > box,
window > grid,
window > stack,
window > paned,
window > box > box,
window > box > grid,
window > box > stack,
window > box > paned,
window > box > box > box,
window > box > box > paned {
  background-color: ${bg};
  color: ${on_surface};
}

/* ══════════════════════════════════════════════════════════════
 * 3. HEADERBAR & TITLEBAR
 * ══════════════════════════════════════════════════════════════ */
headerbar,
.titlebar,
headerbar.titlebar,
.titlebar.horizontal {
  background-color: ${container_high};
  background-image: none;
  color: ${on_surface};
  border-bottom: 1px solid ${outline_variant};
  box-shadow: none;
}
headerbar:backdrop,
.titlebar:backdrop {
  background-color: ${container};
  background-image: none;
  color: ${on_surface_variant};
  box-shadow: none;
}
headerbar .title,
.titlebar .title {
  color: ${on_surface};
  font-weight: 600;
}
headerbar .subtitle,
.titlebar .subtitle {
  color: ${on_surface_variant};
}

/* ══════════════════════════════════════════════════════════════
 * 4. TOOLBAR — Thunar, Nemo primary-toolbar
 * ══════════════════════════════════════════════════════════════ */
toolbar,
toolbar.primary-toolbar,
.toolbar,
.primary-toolbar {
  background-color: ${container_high};
  background-image: none;
  color: ${on_surface};
  box-shadow: none;
}
/* NOTE: border-bottom intentionally omitted here.
 * Chromium/Brave reads the GTK3 toolbar widget's border-bottom to determine
 * the separator thickness between the navigation bar and bookmarks bar.
 * Setting it here causes a visible gap above the bookmarks bar in Brave.
 * File managers (Thunar, Nemo) get their toolbar borders from their own
 * specific overrides below, so they are unaffected. */
toolbar:backdrop,
.toolbar:backdrop,
.primary-toolbar:backdrop {
  background-color: ${container};
}
toolbar button,
toolbar > toolbutton,
.toolbar button,
.primary-toolbar button {
  background-color: transparent;
  background-image: none;
  color: ${on_surface};
  border: none;
  box-shadow: none;
}
toolbar button:hover,
.toolbar button:hover,
.primary-toolbar button:hover {
  background-color: alpha(white, 0.08);
}
toolbar button:active,
.toolbar button:active {
  background-color: alpha(white, 0.16);
}

/* GTK3 file manager headerbars/toolbars */
.nemo-window headerbar,
.nemo-window .titlebar,
.thunar headerbar,
.thunar .titlebar,
.thunar-window headerbar,
.thunar-window .titlebar,
window.thunar,
window.thunar-window,
window.thunar-window.background,
window.thunar-window.background.csd,
window.nemo-window,
window.nemo-window.background,
window.nemo-window.background.csd,
window.nemo-window headerbar,
window.thunar-window headerbar,
.nemo-window toolbar,
.nemo-window toolbar.primary-toolbar,
.thunar toolbar,
.thunar toolbar.primary-toolbar,
.thunar-window toolbar,
.thunar-window toolbar.primary-toolbar,
.thunar box,
.thunar-window box,
.thunar .standard-toolbar,
.thunar-window .standard-toolbar,
.thunar .location-toolbar,
.thunar-window .location-toolbar,
.nemo-window .primary-toolbar,
.thunar .primary-toolbar,
.thunar-window .primary-toolbar {
  background-color: ${container} !important;
  background-image: none !important;
  color: ${on_surface} !important;
  border-color: ${outline_variant} !important;
  box-shadow: none !important;
}
.thunar,
.thunar-window,
window.thunar,
window.thunar-window,
.thunar grid,
.thunar-window grid,
.thunar paned,
.thunar-window paned,
.thunar notebook,
.thunar-window notebook,
.thunar scrolledwindow,
.thunar-window scrolledwindow {
  background-color: ${bg} !important;
  background-image: none !important;
  color: ${on_surface} !important;
}
.thunar headerbar,
.thunar-window headerbar,
.thunar .titlebar,
.thunar-window .titlebar,
.thunar toolbar,
.thunar-window toolbar,
.thunar .standard-toolbar,
.thunar-window .standard-toolbar,
.thunar .location-toolbar,
.thunar-window .location-toolbar,
.thunar .primary-toolbar,
.thunar-window .primary-toolbar {
  background: ${container} !important;
  background-color: ${container} !important;
  background-image: none !important;
  color: ${on_surface} !important;
  border-bottom: 1px solid ${outline_variant} !important;
  box-shadow: none !important;
}
.nemo-window headerbar button,
.nemo-window toolbar button,
.thunar headerbar button,
.thunar toolbar button,
.thunar-window headerbar button,
.thunar-window toolbar button,
.thunar .standard-toolbar button,
.thunar-window .standard-toolbar button,
.thunar .location-toolbar button,
.thunar-window .location-toolbar button,
.nemo-window .linked > button,
.thunar .linked > button,
.thunar-window .linked > button {
  background-color: ${container} !important;
  background-image: none !important;
  color: ${on_surface} !important;
  border-color: ${outline_variant} !important;
  box-shadow: none !important;
}
.nemo-window headerbar button:hover,
.nemo-window toolbar button:hover,
.thunar headerbar button:hover,
.thunar toolbar button:hover,
.thunar-window headerbar button:hover,
.thunar-window toolbar button:hover,
.thunar .standard-toolbar button:hover,
.thunar-window .standard-toolbar button:hover,
.thunar .location-toolbar button:hover,
.thunar-window .location-toolbar button:hover {
  background-color: ${surface_bright} !important;
}

/* ══════════════════════════════════════════════════════════════
 * 5. MENU BAR
 * ══════════════════════════════════════════════════════════════ */
menubar {
  background-color: ${container_high};
  background-image: none;
  color: ${on_surface};
}
menubar > menuitem:hover,
menubar > menuitem:selected {
  background-color: alpha(${primary}, 0.15);
  color: ${on_surface};
}

/* ══════════════════════════════════════════════════════════════
 * 6. MENUS & POPOVERS
 * ══════════════════════════════════════════════════════════════ */
menu,
.menu,
.context-menu {
  background-color: ${container_highest};
  color: ${on_surface};
  border: 1px solid ${outline_variant};
}
menuitem,
.menuitem {
  color: ${on_surface};
}
menuitem:hover,
menuitem:selected {
  background-color: alpha(${primary}, 0.30);
  color: ${selection_fg};
}
menuitem:disabled {
  color: ${on_surface_variant};
}
menu separator,
.menu separator {
  background-color: ${outline_variant};
}

/* ══════════════════════════════════════════════════════════════
 * 7. CONTENT VIEWS — the core fix for Nemo & Thunar content area
 *
 * scrolledwindow > * catches NemoIconContainer (EelCanvas/GtkLayout
 * direct child of GtkScrolledWindow implementing GtkScrollable).
 * nemo-canvas-item is the CSS name set by gtk_widget_class_set_css_name.
 * @define-color base_color above also affects GtkLayout.realize().
 * ══════════════════════════════════════════════════════════════ */
scrolledwindow > *,
scrolledwindow > viewport,
scrolledwindow > viewport > *,
scrolledwindow > treeview,
scrolledwindow > iconview,
viewport,
viewport > *,
nemo-canvas-item {
  background-color: ${surface};
  background-image: none;
  color: ${on_surface};
}

treeview,
treeview.view,
iconview,
iconview > cell {
  background-color: ${surface};
  color: ${on_surface};
  background-image: none;
}
treeview.view:hover {
  background-color: ${container};
}
treeview.view:selected,
treeview.view:selected:focus,
iconview:selected,
iconview:selected:focus,
iconview > cell:selected {
  background-color: ${primary};
  color: ${on_primary};
}
treeview.view:selected:backdrop {
  background-color: ${container};
  color: ${on_surface};
}

/* Explicit Nemo/Thunar content views */
.nemo-window scrolledwindow,
.nemo-window scrolledwindow > viewport,
.nemo-window .view,
.nemo-window treeview,
.nemo-window treeview.view,
.nemo-window iconview,
.nemo-window iconview > cell,
.nemo-window layout,
.nemo-window viewport,
.thunar scrolledwindow,
.thunar scrolledwindow > viewport,
.thunar .view,
.thunar treeview,
.thunar treeview.view,
.thunar iconview,
.thunar iconview > cell,
.thunar layout,
.thunar viewport,
.thunar-window scrolledwindow,
.thunar-window scrolledwindow > viewport,
.thunar-window .view,
.thunar-window treeview,
.thunar-window treeview.view,
.thunar-window iconview,
.thunar-window iconview > cell,
.thunar-window layout,
.thunar-window viewport,
standard-view,
.standard-view {
  background-color: ${surface} !important;
  background-image: none !important;
  color: ${on_surface} !important;
  box-shadow: none !important;
}
.nemo-window nemo-canvas-item,
.thunar standard-view,
.thunar-window standard-view,
.thunar .standard-view,
.thunar-window .standard-view {
  background-color: ${surface} !important;
  background-image: none !important;
  color: ${on_surface} !important;
}

/* ══════════════════════════════════════════════════════════════
 * 8. SIDEBAR
 * ══════════════════════════════════════════════════════════════ */
.sidebar,
.navigation-sidebar,
placessidebar,
placessidebar list,
placessidebar > viewport,
nemo-places-sidebar,
nemo-places-sidebar list,
places-treeview {
  background-color: ${container_low};
  color: ${on_surface};
  background-image: none;
}
.sidebar row,
.navigation-sidebar row,
placessidebar row {
  background-color: transparent;
  color: ${on_surface};
}
.sidebar row:hover,
.navigation-sidebar row:hover,
placessidebar row:hover {
  background-color: alpha(${primary}, 0.08);
}
.sidebar row:selected,
.navigation-sidebar row:selected,
placessidebar row:selected {
  background-color: ${primary};
  color: ${on_primary};
}

/* Explicit Nemo/Thunar sidebars */
.nemo-window .sidebar,
.nemo-window placessidebar,
.nemo-window nemo-places-sidebar,
.thunar .sidebar,
.thunar .shortcuts-pane,
.thunar-window .sidebar,
.thunar-window .shortcuts-pane {
  background-color: ${container_low} !important;
  background-image: none !important;
  color: ${on_surface} !important;
}

/* ══════════════════════════════════════════════════════════════
 * 9. STATUS BAR
 * ══════════════════════════════════════════════════════════════ */
statusbar,
.statusbar {
  background-color: ${container_low};
  color: ${on_surface_variant};
  border-top: 1px solid ${outline_variant};
}

/* ══════════════════════════════════════════════════════════════
 * 10. PATH BAR
 * ══════════════════════════════════════════════════════════════ */
path-bar,
path-bar > button,
path-bar > button.text-button,
path-bar > button.image-button {
  background-color: ${container};
  background-image: none;
  color: ${on_surface};
  box-shadow: none;
}
path-bar > button:hover {
  background-color: ${container_high};
}
path-bar > button:checked,
path-bar > button:active {
  background-color: ${primary};
  background-image: none;
  color: ${on_primary};
}

.nemo-window path-bar,
.nemo-window path-bar > button,
.thunar path-bar,
.thunar path-bar > button,
.thunar-window path-bar,
.thunar-window path-bar > button {
  background-color: ${container_high} !important;
  background-image: none !important;
  color: ${on_surface} !important;
  border-color: ${outline_variant} !important;
}

/* ══════════════════════════════════════════════════════════════
 * 11. ENTRIES (location bar, search)
 * ══════════════════════════════════════════════════════════════ */
entry,
spinbutton {
  background-color: ${container};
  color: ${on_surface};
  border: 1px solid ${outline_variant};
  box-shadow: none;
  background-image: none;
}
entry:focus,
spinbutton:focus {
  border-color: ${primary};
}
entry:disabled {
  background-color: ${container_low};
  color: ${on_surface_variant};
}

.nemo-window entry,
.thunar entry,
.thunar-window entry,
.nemo-window .linked > entry,
.thunar .linked > entry,
.thunar-window .linked > entry {
  background-color: ${container_high} !important;
  background-image: none !important;
  color: ${on_surface} !important;
  border-color: ${outline_variant} !important;
  box-shadow: none !important;
}

/* ══════════════════════════════════════════════════════════════
 * 12. BUTTONS
 * ══════════════════════════════════════════════════════════════ */
button {
  background-color: ${container_high};
  background-image: none;
  color: ${on_surface};
  border: 1px solid ${outline_variant};
  box-shadow: none;
}
button:hover {
  background-color: ${surface_bright};
}
button:active,
button:checked {
  background-color: ${primary};
  color: ${on_primary};
  border-color: ${primary};
}
button:disabled {
  background-color: ${container_low};
  color: ${on_surface_variant};
}
button.suggested-action {
  background-color: ${primary};
  color: ${on_primary};
  border-color: ${primary};
}
button.destructive-action {
  background-color: ${error};
  color: ${on_error};
}
button.flat,
button.flat:hover,
button.flat:active {
  border: none;
  box-shadow: none;
}
button.flat {
  background-color: transparent;
  color: ${on_surface};
}
button.flat:hover {
  background-color: alpha(white, 0.08);
}
button.flat:active,
button.flat:checked {
  background-color: ${primary};
  color: ${on_primary};
}

/* ══════════════════════════════════════════════════════════════
 * 13. NOTEBOOK TABS
 * ══════════════════════════════════════════════════════════════ */
notebook > header {
  background-color: ${container_high};
  border-bottom: 1px solid ${outline_variant};
}
notebook > header tab {
  background-color: transparent;
  color: ${on_surface_variant};
}
notebook > header tab:checked {
  background-color: ${container};
  color: ${on_surface};
  border-bottom: 2px solid ${primary};
}

/* ══════════════════════════════════════════════════════════════
 * 14. SCROLLBAR
 * ══════════════════════════════════════════════════════════════ */
scrollbar {
  background-color: transparent;
}
scrollbar slider {
  background-color: alpha(${on_surface}, 0.3);
  border-radius: 10px;
  min-width: 6px;
  min-height: 6px;
}
scrollbar slider:hover {
  background-color: alpha(${on_surface}, 0.5);
}

/* ══════════════════════════════════════════════════════════════
 * 14b. SCROLL EDGE (overshoot / undershoot)
 * GTK3: overshoot/undershoot are node TYPES, not classes.
 * Use "overshoot.top" not ".overshoot.top" (no leading dot).
 * adw-gtk3-dark uses @window_fg_color radial gradient (white flash).
 * Replace with warm primary tint so it matches our palette.
 * ══════════════════════════════════════════════════════════════ */
overshoot.top {
  background-color: transparent;
  background-image: -gtk-gradient(radial, center top, 0, center top, 0.5,
    to(alpha(${primary}, 0.18)), to(alpha(${primary}, 0)));
  background-size: 100% 100%;
  background-repeat: no-repeat;
  box-shadow: none;
}
overshoot.bottom {
  background-color: transparent;
  background-image: -gtk-gradient(radial, center bottom, 0, center bottom, 0.5,
    to(alpha(${primary}, 0.18)), to(alpha(${primary}, 0)));
  background-size: 100% 100%;
  background-repeat: no-repeat;
  box-shadow: none;
}
overshoot.left {
  background-color: transparent;
  background-image: -gtk-gradient(radial, left center, 0, left center, 0.5,
    to(alpha(${primary}, 0.18)), to(alpha(${primary}, 0)));
  background-size: 100% 100%;
  background-repeat: no-repeat;
  box-shadow: none;
}
overshoot.right {
  background-color: transparent;
  background-image: -gtk-gradient(radial, right center, 0, right center, 0.5,
    to(alpha(${primary}, 0.18)), to(alpha(${primary}, 0)));
  background-size: 100% 100%;
  background-repeat: no-repeat;
  box-shadow: none;
}
undershoot.top {
  background-color: transparent;
  background-image: linear-gradient(to bottom, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}
undershoot.bottom {
  background-color: transparent;
  background-image: linear-gradient(to top, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}
undershoot.left {
  background-color: transparent;
  background-image: linear-gradient(to right, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}
undershoot.right {
  background-color: transparent;
  background-image: linear-gradient(to left, alpha(${outline_variant}, 0.2), transparent);
  box-shadow: none;
}

/* ══════════════════════════════════════════════════════════════
 * 15. SELECTION
 * ══════════════════════════════════════════════════════════════ */
selection {
  background-color: ${primary};
  color: ${on_primary};
}

/* ══════════════════════════════════════════════════════════════
 * 16. FRAME & SEPARATOR
 * ══════════════════════════════════════════════════════════════ */
separator,
.separator {
  background-color: ${outline_variant};
}
frame > border {
  border-color: ${outline_variant};
}

/* ══════════════════════════════════════════════════════════════
 * 17. INFOBAR
 * ══════════════════════════════════════════════════════════════ */
infobar.info    > revealer > box { background-color: ${container_high}; color: ${on_surface}; }
infobar.warning > revealer > box { background-color: ${warning_color};  color: ${bg}; }
infobar.error   > revealer > box { background-color: ${error};          color: ${on_error}; }

/* ══════════════════════════════════════════════════════════════
 * 18. TOOLTIP
 * ══════════════════════════════════════════════════════════════ */
tooltip {
  background-color: ${surface_bright};
  color: ${on_surface};
  border: 1px solid ${outline_variant};
}

/* ══════════════════════════════════════════════════════════════
 * 19. LABEL
 * ══════════════════════════════════════════════════════════════ */
label {
  color: ${on_surface};
}
label:disabled {
  color: ${on_surface_variant};
}

GTK3CSS
)

# ── Write quickshell sub-files ─────────────────────────────────────────────────
{ printf '%s\n' "$gtk3_colors_css" | sed 's/ !important//g'
  # Recent Chromium/Brave builds read headerbar border-bottom for the toolbar separator
  # height (older builds used `toolbar` border-bottom, which is intentionally omitted above).
  printf '\n/* Chromium/Brave: zero out headerbar border-bottom — GTK CSS classes match WM class */\nwindow.background.google-chrome headerbar,\nwindow.background.google-chrome headerbar:backdrop,\nwindow.background.google-chrome .titlebar,\nwindow.background.brave-browser headerbar,\nwindow.background.brave-browser headerbar:backdrop,\nwindow.background.brave-browser .titlebar,\nwindow.background.chromium headerbar,\nwindow.background.chromium headerbar:backdrop,\nwindow.background.chromium .titlebar {\n  border-bottom: none;\n}\n'
} > "$gtk3_dir/quickshell/colors.css"
printf '%s\n' "$colors_css"      > "$gtk4_dir/quickshell/colors.css"
printf '%s\n' "/* geometry — GTK4 only */" > "$gtk3_dir/quickshell/geometry.css"
printf '%s\n' "$geometry_css"             > "$gtk4_dir/quickshell/geometry.css"

# ── GTK3 entry point ──────────────────────────────────────────────────────────
entry_css='/* Generated by Quickshell GTK bridge. */\n@import url("quickshell/colors.css");\n@import url("quickshell/geometry.css");'
[ -L "$gtk3_dir/gtk.css" ] && rm -f "$gtk3_dir/gtk.css"
printf '%b\n' "$entry_css" > "$gtk3_dir/gtk.css"

# ── GTK4 user CSS — colour tokens + direct overrides ONLY ─────────────────────
#
# Architecture: the WhiteSur theme GResource is already loaded by GTK as *theme*
# (author) CSS.  User CSS (~/.config/gtk-4.0/gtk.css) has higher cascade priority
# than theme CSS for both @define-color tokens AND direct CSS rules.
#
# We must NOT put the full WhiteSur structural CSS into user CSS — that creates a
# duplicate/competing copy in the same cascade layer where our token declarations
# and structural rules fight each other on specificity.
#
# Correct model:
#   theme CSS  → WhiteSur GResource (structural widgets using @named_colors)
#   user CSS   → our @define-color declarations + direct !important overrides
#
# The @define-color in user CSS overrides libadwaita's embedded @define-color
# (user CSS > app/author CSS in GTK's cascade).  Our direct rules with !important
# override the WhiteSur theme rules (user !important > author !important > normal).

# Write the MaterialYou GTK theme into ~/.themes/MaterialYou/.
# GTK3: Materia-dark provides Material Design widget structure; we recolour it
#        with our system palette by overriding its @define-color tokens.
# GTK4: Materia-dark provides structure for non-libadwaita apps; our full
#        colors_css overrides both Materia's tokens and libadwaita's custom
#        properties so every GTK4 app gets system colours.
# This creates a nwg-look-visible theme entry that updates on every colour change.
_write_materialyou_theme() {
  mkdir -p "$materialyou_dir/gtk-3.0" "$materialyou_dir/gtk-4.0"

  cat > "$materialyou_dir/index.theme" << 'ITHEME'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=MaterialYou
Comment=Dynamic Material You colors extracted from wallpaper
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=MaterialYou
MetacityTheme=MaterialYou
ButtonLayout=close,minimize,maximize:menu
ITHEME

  # GTK3: Materia-dark for widget structure, Material You palette on top.
  # @define-color declarations after the @import override Materia's token values,
  # so every widget that reads @theme_bg_color etc. gets our system colours.
  {
    printf '@import url("/usr/share/themes/Materia-dark/gtk-3.0/gtk.css");\n\n'
    printf '/* Material You colour tokens — override Materia-dark defaults */\n\n'
    printf '%s\n' "$gtk3_colors_css" | sed 's/ !important//g'
    # Extra Materia-specific tokens not covered by the shared gtk3_colors_css block
    printf '@define-color wm_title              %s;\n' "$on_surface"
    printf '@define-color wm_unfocused_title     %s;\n' "$on_surface_variant"
    printf '@define-color wm_unfocused_bg        %s;\n' "$container"
    printf '@define-color xfwm4_title            %s;\n' "$on_surface"
    printf '@define-color xfwm4_unfocused_title  %s;\n' "$on_surface_variant"
  } > "$materialyou_dir/gtk-3.0/gtk.css"

  # GTK4: Materia-dark structure for non-libadwaita apps; our colors_css covers
  # both the @define-color token overrides and explicit libadwaita CSS custom
  # property overrides so every GTK4 app (adw or plain) gets system colours.
  # The file also doubles as the symlink target when GNOME's settings daemon
  # recreates ~/.config/gtk-4.0/gtk.css — so it must be self-contained.
  {
    printf '@import url("/usr/share/themes/Materia-dark/gtk-4.0/gtk.css");\n\n'
    printf '/* Material You overrides — generated by applygtk.sh */\n\n'
    printf '%s\n' "$colors_css"   | sed 's/ !important//g'
    printf '\n%s\n' "$geometry_css" | sed 's/ !important//g'
  } > "$materialyou_dir/gtk-4.0/gtk.css"
  cp "$materialyou_dir/gtk-4.0/gtk.css" "$materialyou_dir/gtk-4.0/gtk-dark.css"
}

write_gtk4_useronly() {
  local target="$1"
  local tmp_target
  [ -L "$target" ] && rm -f "$target"
  tmp_target=$(mktemp)
  printf '/* Generated by Quickshell — colour tokens + overrides only.\n'        >> "$tmp_target"
  printf ' * MaterialYou structural CSS is loaded separately as GTK theme CSS.\n' >> "$tmp_target"
  printf ' * Do not edit — regenerated by applygtk.sh on every colour change. */\n\n' >> "$tmp_target"
  # GTK4 4.14+ rejects !important in user CSS (provider priority 800 already
  # beats application CSS priority 600, so !important is not needed and causes
  # parse errors that silently drop the entire declaration).
  printf '%s\n' "$colors_css"   | sed 's/ !important//g' >> "$tmp_target"
  printf '\n%s\n' "$geometry_css" | sed 's/ !important//g' >> "$tmp_target"
  # Chromium/Brave separator fixes — must live in user CSS (priority 800) to outrank
  # theme CSS (priority 200) regardless of specificity.
  #
  # 1. button#button border-color: Chrome/Brave sample this GTK widget to determine
  #    the colour of the toolbar↔content separator line.  Our generated `button {}`
  #    rule above sets a visible border; the higher-specificity `button#button` rule
  #    below resets it to transparent so no coloured line is drawn.
  #
  # 2. headerbar border-bottom: Recent Chromium builds read headerbar's border-bottom
  #    to set the separator *height* (previously they used `toolbar`, which is already
  #    intentionally omitted).  Zero it out for .background.chromium windows only so
  #    regular GTK4 app headerbars keep their bottom border.
  printf '\n/* ── Chromium / Brave separator fixes ───────────────────────────────────────
 * Must live in user CSS (priority 800) to outrank the theme layer (priority 200).
 * GTK CSS classes match the WM class: google-chrome, brave-browser, chromium.
 *
 * 1. button#button border-color: Chrome/Brave create a GtkButton named "button"
 *    and sample its border-color to colour the toolbar↔content separator line.
 *    Our generated `button {}` rule sets a visible colour; the higher-specificity
 *    `button#button` rule resets it to transparent.
 *
 * 2. headerbar border-bottom: Recent Chromium builds read the headerbar border-bottom
 *    to set the separator height (previously they used `toolbar`, which is already
 *    intentionally omitted).  Target only browser windows by their GTK CSS class.
 */
button#button {
  border-color: transparent;
  box-shadow: none;
}

.background.google-chrome frame,
.background.google-chrome frame > border,
.background.brave-browser frame,
.background.brave-browser frame > border,
.background.chromium frame,
.background.chromium frame > border {
  border-color: transparent;
  box-shadow: none;
}

.background.google-chrome headerbar,
.background.google-chrome headerbar:backdrop,
.background.google-chrome .titlebar,
.background.brave-browser headerbar,
.background.brave-browser headerbar:backdrop,
.background.brave-browser .titlebar,
.background.chromium headerbar,
.background.chromium headerbar:backdrop,
.background.chromium .titlebar {
  border-bottom: none;
}
' >> "$tmp_target"
  mv "$tmp_target" "$target"
}

write_gtk4_useronly "$gtk4_dir/gtk.css"
write_gtk4_useronly "$gtk4_dir/gtk-dark.css"
_write_materialyou_theme

# ── Qt5ct / Qt6ct color palette ───────────────────────────────────────────────
apply_qtct() {
  local qt5ct_dir="$XDG_CONFIG_HOME/qt5ct"
  local qt6ct_dir="$XDG_CONFIG_HOME/qt6ct"
  [ -d "$qt5ct_dir" ] || return 0

  mkdir -p "$qt5ct_dir/colors" "$qt6ct_dir/colors"

  # Qt ARGB helpers
  argb()   { printf '#ff%s' "${1#\#}"; }   # fully opaque
  argb55() { printf '#8c%s' "${1#\#}"; }   # 55% opacity
  argb45() { printf '#73%s' "${1#\#}"; }   # 45% opacity (disabled)
  argb30() { printf '#4d%s' "${1#\#}"; }   # 30% opacity (placeholder)

  local surface_lowest
  surface_lowest=$(get_color "surface_container_lowest" "#0e0e0e")

  # QPalette 21 roles (in order):
  # WindowText, Button, Light, Midlight, Dark, Mid, Text, BrightText,
  # ButtonText, Base, Window, Shadow, Highlight, HighlightedText,
  # Link, LinkVisited, AlternateBase, NoRole, ToolTipBase, ToolTipText,
  # PlaceholderText

  local a_wt=$(argb   "$on_bg")               # WindowText
  local a_btn=$(argb  "$container_high")      # Button bg
  local a_lgt=$(argb  "$surface_bright")      # Light (lighter than button)
  local a_mlt=$(argb  "$container_highest")   # Midlight
  local a_drk=$(argb  "$surface_lowest")      # Dark (darker than button)
  local a_mid=$(argb  "$container_low")       # Mid
  local a_txt=$(argb  "$on_surface")          # Text (in views)
  local a_brt=$(argb  "#ffffff")              # BrightText (high-contrast white)
  local a_btt=$(argb  "$on_surface_variant")  # ButtonText
  local a_bas=$(argb  "$surface")             # Base (view bg)
  local a_win=$(argb  "$bg")                  # Window bg
  local a_shd=$(argb  "$container_lowest")    # Shadow
  local a_hl=$(argb   "$primary")             # Highlight (selection bg)
  local a_hlt=$(argb  "$on_primary")          # HighlightedText
  local a_lnk=$(argb  "$primary")             # Link
  local a_lnv=$(argb  "$secondary")           # LinkVisited
  local a_alt=$(argb  "$container_low")       # AlternateBase (alternate row)
  local a_nor=$(argb  "$container_lowest")    # NoRole
  local a_ttb=$(argb  "$surface_bright")      # ToolTipBase
  local a_ttt=$(argb  "$on_surface")          # ToolTipText
  local a_ph=$(argb55 "$on_surface_variant")  # PlaceholderText

  local active="${a_wt}, ${a_btn}, ${a_lgt}, ${a_mlt}, ${a_drk}, ${a_mid}, ${a_txt}, ${a_brt}, ${a_btt}, ${a_bas}, ${a_win}, ${a_shd}, ${a_hl}, ${a_hlt}, ${a_lnk}, ${a_lnv}, ${a_alt}, ${a_nor}, ${a_ttb}, ${a_ttt}, ${a_ph}"

  # Disabled: text/fg roles at 45% opacity, backgrounds unchanged
  local d_wt=$(argb45  "$on_bg")
  local d_txt=$(argb45 "$on_surface")
  local d_btt=$(argb45 "$on_surface_variant")
  local d_ttt=$(argb45 "$on_surface")
  local d_ph=$(argb30  "$on_surface_variant")

  local disabled="${d_wt}, ${a_btn}, ${a_lgt}, ${a_mlt}, ${a_drk}, ${a_mid}, ${d_txt}, ${a_brt}, ${d_btt}, ${a_bas}, ${a_win}, ${a_shd}, ${a_hl}, ${a_hlt}, ${a_lnk}, ${a_lnv}, ${a_alt}, ${a_nor}, ${a_ttb}, ${d_ttt}, ${d_ph}"

  # Inactive: same as active but with slightly dimmed highlights
  local i_hl=$(argb "$secondary_container")
  local i_hlt=$(argb "$on_secondary_container")
  local inactive="${a_wt}, ${a_btn}, ${a_lgt}, ${a_mlt}, ${a_drk}, ${a_mid}, ${a_txt}, ${a_brt}, ${a_btt}, ${a_bas}, ${a_win}, ${a_shd}, ${i_hl}, ${i_hlt}, ${a_lnk}, ${a_lnv}, ${a_alt}, ${a_nor}, ${a_ttb}, ${a_ttt}, ${a_ph}"

  local scheme
  scheme=$(printf '[ColorScheme]\nactive_colors=%s\ndisabled_colors=%s\ninactive_colors=%s\n' \
    "$active" "$disabled" "$inactive")

  printf '%s\n' "$scheme" > "$qt5ct_dir/colors/material-you.conf"
  [ -d "$qt6ct_dir" ] && printf '%s\n' "$scheme" > "$qt6ct_dir/colors/material-you.conf"

  for conf in "$qt5ct_dir/qt5ct.conf" "$qt6ct_dir/qt6ct.conf"; do
    [ -f "$conf" ] || continue
    if grep -q '^color_scheme_path=' "$conf"; then
      sed -i "s|^color_scheme_path=.*|color_scheme_path=$(dirname "$conf")/colors/material-you.conf|" "$conf"
    fi
    if grep -q '^custom_palette=' "$conf"; then
      sed -i 's/^custom_palette=.*/custom_palette=true/' "$conf"
    fi
    if grep -q '^style=' "$conf"; then
      sed -i 's/^style=.*/style=kvantum/' "$conf"
    fi
  done
}

apply_qtct

# ── Kvantum theme colors ──────────────────────────────────────────────────────
apply_kvantum() {
  local kvconfig="$XDG_CONFIG_HOME/Kvantum/MaterialAdw/MaterialAdw.kvconfig"
  local kvsvg="$XDG_CONFIG_HOME/Kvantum/MaterialAdw/MaterialAdw.svg"
  [ -f "$kvconfig" ] || return 0

  # Patch SVG color-scheme classes
  if [ -f "$kvsvg" ]; then
    # Replace ColorScheme class color values (used by Kvantum engine)
    # Try to match the existing hex values and replace them
    sed -i \
      -e "s|\.ColorScheme-Highlight[[:space:]]*{[^}]*}|.ColorScheme-Highlight { color:${primary}; stop-color:${primary}; }|" \
      -e "s|\.ColorScheme-Background[[:space:]]*{[^}]*}|.ColorScheme-Background { color:${bg}; stop-color:${bg}; }|" \
      -e "s|\.ColorScheme-ButtonBackground[[:space:]]*{[^}]*}|.ColorScheme-ButtonBackground { color:${container_high}; stop-color:${container_high}; }|" \
      -e "s|\.ColorScheme-Text[[:space:]]*{[^}]*}|.ColorScheme-Text { color:${on_surface}; stop-color:${on_surface}; }|" \
      -e "s|\.ColorScheme-NormalText[[:space:]]*{[^}]*}|.ColorScheme-NormalText { color:${on_surface}; stop-color:${on_surface}; }|" \
      -e "s|\.ColorScheme-HighlightedText[[:space:]]*{[^}]*}|.ColorScheme-HighlightedText { color:${on_primary}; stop-color:${on_primary}; }|" \
      -e "s|\.ColorScheme-PositiveText[[:space:]]*{[^}]*}|.ColorScheme-PositiveText { color:${success_color}; stop-color:${success_color}; }|" \
      -e "s|\.ColorScheme-NeutralText[[:space:]]*{[^}]*}|.ColorScheme-NeutralText { color:${warning_color}; stop-color:${warning_color}; }|" \
      -e "s|\.ColorScheme-NegativeText[[:space:]]*{[^}]*}|.ColorScheme-NegativeText { color:${error}; stop-color:${error}; }|" \
      "$kvsvg"

    # Also do a broad hex replacement of known hardcoded originals
    sed -i \
      -e "s|#0F1416|${bg}|gI" \
      -e "s|#84D2E7|${primary}|gI" \
      -e "s|#B2CBD2|${on_surface_variant}|gI" \
      -e "s|#CEE7EF|${secondary_container}|gI" \
      -e "s|#eff0f1|${bg}|gI" \
      -e "s|#fcfcfc|${surface_bright}|gI" \
      -e "s|#DEE3E5|${on_surface}|gI" \
      -e "s|#dee3e5|${on_surface}|gI" \
      "$kvsvg"
  fi

  # Patch GeneralColors section
  sed -i \
    -e "s|^window\.color=.*|window.color=${bg}|" \
    -e "s|^base\.color=.*|base.color=${surface}|" \
    -e "s|^alt\.base\.color=.*|alt.base.color=${container_low}|" \
    -e "s|^button\.color=.*|button.color=${container_high}|" \
    -e "s|^light\.color=.*|light.color=${surface_bright}|" \
    -e "s|^mid\.light\.color=.*|mid.light.color=${container_highest}|" \
    -e "s|^dark\.color=.*|dark.color=${container_lowest}|" \
    -e "s|^mid\.color=.*|mid.color=${container_low}|" \
    -e "s|^highlight\.color=.*|highlight.color=${primary}|" \
    -e "s|^inactive\.highlight\.color=.*|inactive.highlight.color=${secondary_container}|" \
    -e "s|^text\.color=.*|text.color=${on_surface}|" \
    -e "s|^window\.text\.color=.*|window.text.color=${on_bg}|" \
    -e "s|^button\.text\.color=.*|button.text.color=${on_surface}|" \
    -e "s|^disabled\.text\.color=.*|disabled.text.color=${on_surface_variant}|" \
    -e "s|^tooltip\.text\.color=.*|tooltip.text.color=${on_surface}|" \
    -e "s|^highlight\.text\.color=.*|highlight.text.color=${on_primary}|" \
    -e "s|^link\.color=.*|link.color=${primary}|" \
    -e "s|^link\.visited\.color=.*|link.visited.color=${secondary}|" \
    -e "s|^progress\.indicator\.text\.color=.*|progress.indicator.text.color=${on_primary}|" \
    "$kvconfig"

  # Fix per-section text colors (previously hardcoded #DEE3E5)
  sed -i \
    -e "s|^text\.normal\.color=#DEE3E5|text.normal.color=${on_surface}|g" \
    -e "s|^text\.focus\.color=#DEE3E5|text.focus.color=${on_surface}|g" \
    -e "s|^text\.normal\.color=#dee3e5|text.normal.color=${on_surface}|g" \
    -e "s|^text\.focus\.color=#dee3e5|text.focus.color=${on_surface}|g" \
    -e "s|^text\.press\.color=white|text.press.color=${on_primary}|g" \
    -e "s|^text\.toggle\.color=#ffffff|text.toggle.color=${on_primary}|g" \
    -e "s|^text\.toggle\.color=white|text.toggle.color=${on_primary}|g" \
    -e "s|^text\.disabled\.color=#0F1416|text.disabled.color=${on_surface_variant}|g" \
    "$kvconfig"
}

apply_kvantum

# ── Map primary hex colour to the nearest GNOME accent name ──────────────────
# GNOME 47+ only accepts a fixed enum for accent-color.
# This picks the enum value whose hue is closest to the primary colour's hue.
pick_gnome_accent() {
  local hex="${1#'#'}"
  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))
  awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN {
    max = r; if (g > max) max = g; if (b > max) max = b
    min = r; if (g < min) min = g; if (b < min) min = b
    delta = max - min
    # Achromatic → slate
    if (delta == 0 || max == 0) { print "slate"; exit }
    # Saturation check — very desaturated → slate
    sat = delta / max
    if (sat < 0.15) { print "slate"; exit }
    # Hue in degrees
    if (max == r) hue = 60 * (((g - b) / delta) % 6)
    else if (max == g) hue = 60 * ((b - r) / delta + 2)
    else               hue = 60 * ((r - g) / delta + 4)
    if (hue < 0) hue += 360
    # Map hue → accent name
    if      (hue <  15 || hue >= 345) print "red"
    else if (hue <  45)               print "orange"
    else if (hue <  75)               print "yellow"
    else if (hue < 150)               print "green"
    else if (hue < 195)               print "teal"
    else if (hue < 255)               print "blue"
    else if (hue < 315)               print "purple"
    else                              print "pink"
  }'
}

# ── Sync theme settings to all GTK/X11 config files ──────────────────────────
# Mirrors what the GTK settings app exports:
#   ~/.config/gtk-3.0/settings.ini, ~/.gtkrc-2.0, ~/.icons/default/index.theme,
#   ~/.config/xsettingsd/xsettingsd.conf, ~/.config/gtk-4.0/*
sync_gtk_settings() {
  local gtk_theme icon_theme cursor_theme font_name prefer_dark
  gtk_theme="MaterialYou"
  icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme     2>/dev/null | tr -d "'")
  cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
  font_name=$(gsettings get org.gnome.desktop.interface font-name       2>/dev/null | tr -d "'")
  prefer_dark=$(gsettings get org.gnome.desktop.interface color-scheme  2>/dev/null | grep -q "dark" && echo 1 || echo 0)

  [ -z "$icon_theme" ]   && icon_theme="Papirus"
  [ -z "$cursor_theme" ] && cursor_theme="Bibata-Modern-Classic"
  [ -z "$font_name" ]    && font_name="Sans 11"

  # Set GNOME accent colour from the wallpaper-derived primary
  local gnome_accent
  gnome_accent=$(pick_gnome_accent "$primary")
  gsettings set org.gnome.desktop.interface accent-color "$gnome_accent" 2>/dev/null || true

  # ── ~/.config/gtk-3.0/settings.ini ─────────────────────────────────────────
  local s3="$gtk3_dir/settings.ini"
  if [ -f "$s3" ]; then
    sed -i \
      -e "s|^gtk-theme-name=.*|gtk-theme-name=${gtk_theme}|" \
      -e "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=${icon_theme}|" \
      -e "s|^gtk-cursor-theme-name=.*|gtk-cursor-theme-name=${cursor_theme}|" \
      -e "s|^gtk-font-name=.*|gtk-font-name=${font_name}|" \
      -e "s|^gtk-application-prefer-dark-theme=.*|gtk-application-prefer-dark-theme=${prefer_dark}|" \
      "$s3"
  fi

  # ── ~/.config/gtk-4.0/settings.ini ─────────────────────────────────────────
  local s4="$gtk4_dir/settings.ini"
  if [ -f "$s4" ]; then
    sed -i \
      -e "s|^gtk-theme-name=.*|gtk-theme-name=${gtk_theme}|" \
      -e "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=${icon_theme}|" \
      -e "s|^gtk-cursor-theme-name=.*|gtk-cursor-theme-name=${cursor_theme}|" \
      -e "s|^gtk-font-name=.*|gtk-font-name=${font_name}|" \
      -e "s|^gtk-application-prefer-dark-theme=.*|gtk-application-prefer-dark-theme=${prefer_dark}|" \
      "$s4"
  fi

  # ── ~/.gtkrc-2.0 ───────────────────────────────────────────────────────────
  local gtkrc2="$HOME/.gtkrc-2.0"
  if [ -f "$gtkrc2" ]; then
    sed -i \
      -e "s|^gtk-theme-name=.*|gtk-theme-name=\"${gtk_theme}\"|" \
      -e "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=\"${icon_theme}\"|" \
      -e "s|^gtk-cursor-theme-name=.*|gtk-cursor-theme-name=\"${cursor_theme}\"|" \
      -e "s|^gtk-font-name=.*|gtk-font-name=\"${font_name}\"|" \
      "$gtkrc2"
  fi

  # ── ~/.icons/default/index.theme ───────────────────────────────────────────
  local icons_theme="$HOME/.icons/default/index.theme"
  if [ -f "$icons_theme" ]; then
    sed -i "s|^Inherits=.*|Inherits=${cursor_theme}|" "$icons_theme"
  fi

  # ── ~/.config/xsettingsd/xsettingsd.conf ───────────────────────────────────
  local xsd="$XDG_CONFIG_HOME/xsettingsd/xsettingsd.conf"
  if [ -f "$xsd" ]; then
    sed -i \
      -e "s|^Net/ThemeName .*|Net/ThemeName \"${gtk_theme}\"|" \
      -e "s|^Net/IconThemeName .*|Net/IconThemeName \"${icon_theme}\"|" \
      -e "s|^Gtk/CursorThemeName .*|Gtk/CursorThemeName \"${cursor_theme}\"|" \
      "$xsd"
    # Reload xsettingsd if running so X11/XWayland apps pick up changes immediately
    pkill -HUP xsettingsd 2>/dev/null || true
  fi

  # ── org.cinnamon.desktop.interface (Nemo reads this, not org.gnome) ─────────
  if gsettings list-schemas 2>/dev/null | grep -q "^org.cinnamon.desktop.interface$"; then
    gsettings set org.cinnamon.desktop.interface gtk-theme    "$gtk_theme"   2>/dev/null || true
    gsettings set org.cinnamon.desktop.interface icon-theme   "$icon_theme"  2>/dev/null || true
    gsettings set org.cinnamon.desktop.interface cursor-theme "$cursor_theme" 2>/dev/null || true
  fi

  # ── User session environment — pin GTK_THEME away from stale old themes ────
  # Some apps inherit GTK_THEME from an earlier imported session environment,
  # which bypasses settings.ini and makes the generated wallpaper colors appear
  # to do nothing. Write the current GTK theme explicitly for new logins.
  local envd_dir="$XDG_CONFIG_HOME/environment.d"
  local gtk_env_file="$envd_dir/90-gtk-theme.conf"
  mkdir -p "$envd_dir"
  cat > "$gtk_env_file" <<EOF
GTK_THEME=$gtk_theme
EOF

  # ── Systemd user environment — unset GTK_THEME so GTK reads settings.ini ───
  # A stale GTK_THEME pointing to a missing theme causes GTK to fall back to
  # Adwaita light, overriding everything. Keep it unset; settings.ini wins.
  systemctl --user unset-environment GTK_THEME 2>/dev/null || true
}

sync_gtk_settings

# ── Thunderbird accent ──────────────────────────────────────────────────────
# AccentColor in Gecko resolves to the GNOME accent enum (e.g. "orange"),
# not our exact Material You primary hex. Write the hex directly so every
# --tb-accent reference in Thunderbird uses our precise palette colour.
_apply_thunderbird_accent() {
  local tb_dir="$HOME/.thunderbird"
  [ -f "$tb_dir/profiles.ini" ] || return 0

  # Find the default profile path (entry with Default=1)
  local profile_path
  profile_path=$(awk -F= '
    /^\[Profile/ { in_profile=1; is_default=0; path="" }
    in_profile && /^Default=1/ { is_default=1 }
    in_profile && /^Path=/ { path=$2 }
    in_profile && /^$/ { if (is_default && path) { print path; exit } }
    END { if (is_default && path) print path }
  ' "$tb_dir/profiles.ini" 2>/dev/null)
  [ -z "$profile_path" ] && return 0

  local chrome_dir="$tb_dir/$profile_path/chrome"
  [ -d "$chrome_dir" ] || return 0

  # Write materialyou-accent.css — exact hex, no AccentColor approximation
  cat > "$chrome_dir/materialyou-accent.css" << TBCSS
/* Material You accent for Thunderbird — generated by applygtk.sh. Do not edit. */

/* --tb-accent with id+attr specificity to beat :root-only rules */
:root#messengerWindow,
:root[windowtype="mail:3pane"],
:root[windowtype="mail:messageWindow"],
:root[windowtype="msgcompose"],
:root[windowtype="Calendar:EventDialog"],
:root[windowtype="Tasks:TasksTab"] {
  --tb-accent: ${primary} !important;
}

@media (prefers-color-scheme: dark) {
  :root#messengerWindow,
  :root[windowtype="mail:3pane"],
  :root[windowtype="mail:messageWindow"],
  :root[windowtype="msgcompose"],
  :root[windowtype="Calendar:EventDialog"],
  :root[windowtype="Tasks:TasksTab"] {
    --tb-accent: ${primary} !important;
  }
}

/* Tasks / calendar sort / column headers — use a tint of the accent
   instead of whatever Lightbird's --lb-panel-bgcolor gives them */
.list-header-bar th,
.list-header-bar .column-header,
calendar-task-tree .list-header-bar,
#calendar-task-tree .list-header-bar,
.tasks-list-pane .list-header-bar,
treecol,
.task-list-header {
  background-color: color-mix(in srgb, ${primary} 16%, transparent) !important;
  border-bottom: 1.5px solid color-mix(in srgb, ${primary} 45%, transparent) !important;
}

/* Active/sorted column indicator */
treecol[sortDirection],
.list-header-bar th[sort-direction],
.list-header-bar th[aria-sort] {
  background-color: color-mix(in srgb, ${primary} 28%, transparent) !important;
  color: ${primary} !important;
}

/* Primary / default buttons */
button.primary,
.button.primary,
button[is="button-link"].primary,
.notification-button.primary {
  background-color: ${primary} !important;
  color: ${on_primary} !important;
  border-color: ${primary} !important;
}
button.primary:hover,
.button.primary:hover {
  background-color: ${primary_container} !important;
}
TBCSS

  # Patch userChrome.css: replace AccentColor references with exact hex so
  # the import above is guaranteed to be consistent when Gecko resolves vars.
  local uc="$chrome_dir/userChrome.css"
  if [ -f "$uc" ]; then
    # Add @import as very first line if not already present
    if ! grep -q 'materialyou-accent\.css' "$uc"; then
      local tmp
      tmp=$(mktemp)
      printf '@import "materialyou-accent.css";\n' > "$tmp"
      cat "$uc" >> "$tmp"
      mv "$tmp" "$uc"
    fi
    # Replace bare and !important AccentColor with our primary hex
    sed -i "s/--tb-accent: AccentColor !important/--tb-accent: ${primary} !important/g" "$uc"
    sed -i "s/--tb-accent: AccentColor;/--tb-accent: ${primary};/g" "$uc"
  fi
}

_apply_thunderbird_accent

# WhiteSur integration intentionally disabled.


# ── Notify running GTK apps to reload their CSS ────────────────────────────
# Toggling gtk-theme tricks GTK4/libadwaita apps into reloading user CSS.
# We flip to a non-existent variant and back to the real theme.
reload_gtk_theme() {
  local current_theme
  current_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
  if [ -n "$current_theme" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita" 2>/dev/null || true
    sleep 0.1
    gsettings set org.gnome.desktop.interface gtk-theme "$current_theme" 2>/dev/null || true
    # Re-apply our CSS in case GNOME recreated symlinks during the theme toggle.
    sleep 0.3
    write_gtk4_useronly "$gtk4_dir/gtk.css"
    write_gtk4_useronly "$gtk4_dir/gtk-dark.css"
  fi
}

reload_gtk_theme
