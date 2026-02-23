#!/usr/bin/env bash
# Active ou désactive l'auto-approbation des outils élevés
source "$(dirname "$0")/common.sh"
load_env

MODE="${1:-}"
[ -z "$MODE" ] && error "Usage: $0 <on|off|status>"

CONFIG="$DATA_DIR/openclaw.json"
[ -f "$CONFIG" ] || error "Config introuvable: $CONFIG"

case "$MODE" in
  on)
    info "Activation de l'auto-approbation..."
    python3 -c "
import json, sys
p='$CONFIG'
obj=json.load(open(p))
obj.setdefault('agents',{}).setdefault('defaults',{})['elevatedDefault']='full'
obj.setdefault('tools',{}).setdefault('elevated',{})['enabled']=True
with open(p,'w') as f: json.dump(obj,f,indent=2)
"
    ok "Auto-approbation activée (elevatedDefault=full)"
    ;;
  off)
    info "Désactivation de l'auto-approbation..."
    python3 -c "
import json, sys
p='$CONFIG'
obj=json.load(open(p))
obj.setdefault('agents',{}).setdefault('defaults',{})['elevatedDefault']='ask'
with open(p,'w') as f: json.dump(obj,f,indent=2)
"
    ok "Auto-approbation désactivée (elevatedDefault=ask)"
    ;;
  status)
    VAL=$(python3 -c "
import json
p='$CONFIG'
obj=json.load(open(p))
v=obj.get('agents',{}).get('defaults',{}).get('elevatedDefault','ask')
print(v)
")
    if [ "$VAL" = "full" ]; then
      ok "Auto-approbation: ON (elevatedDefault=$VAL)"
    else
      info "Auto-approbation: OFF (elevatedDefault=$VAL)"
    fi
    exit 0
    ;;
  *)
    error "Mode invalide: $MODE (utilise on, off ou status)"
    ;;
esac

# Hot reload du gateway si il tourne
if gateway_is_running; then
  info "Hot reload du gateway..."
  docker kill --signal=SIGUSR1 "$CONTAINER_NAME" >/dev/null
  ok "Gateway rechargé"
else
  warn "Gateway non démarré, la config sera appliquée au prochain démarrage"
fi
