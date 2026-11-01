#!/usr/bin/env bash
# Link router: the default http(s) handler. Desk app links (Linear, Notion, Gmail, Notion Calendar) open as that app's window on its desk (desk-app.sh open),
#   everything else goes to Vivaldi as before.
# Why: the desk apps are all Vivaldi, so xdg-open sent their links to whichever Vivaldi window was last active, as a tab.
# Covers links opened outside Vivaldi (xdg-open, the portal: VS Code, terminals, Electron apps). A link clicked inside a Vivaldi window
#   (e.g. Linear in the Slack app) never reaches it: Vivaldi opens those itself.
# Slack (<team>.slack.com/archives/...) isn't routed: those URLs need the team id to map onto app.slack.com/client.
desk=~/.config/hypr/custom/scripts/desk-app.sh
url="${1:-}"
case "$url" in
  https://linear.app/*)                              app=linear ;;
  https://mail.google.com/*)                         app=gmail ;;
  https://calendar.notion.so/*)                      app=calendar ;;
  https://app.notion.com/*)                          app=notion ;;
  https://notion.so/*|https://www.notion.so/*)       app=notion url="https://app.notion.com/${url#https://*notion.so/}" ;;   # same page ids
esac
# Fall back to a Vivaldi tab when it isn't a desk app link, or Hyprland can't be reached (no session env)
if [ -n "${app:-}" ] && [ $# -eq 1 ] && hyprctl version >/dev/null 2>&1; then
  "$desk" "$app" open "$url" && exit
fi
exec vivaldi "$@"
