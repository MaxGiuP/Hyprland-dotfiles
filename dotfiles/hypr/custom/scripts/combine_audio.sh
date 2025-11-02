#!/usr/bin/env bash
set -e

# Riavvia lo stack audio per partire puliti
systemctl --user restart pipewire pipewire-pulse wireplumber

#### Combined Audio Setup ####

# 1) Rimuovi eventuali istanze precedenti del combine sink "CombinedStereo"
pactl list short modules \
| awk '/sink_name=CombinedStereo/ {print $1}' \
| while read -r mid; do
    pactl unload-module "$mid"
done

# 2) Imposta il profilo della scheda NVidia su pro-audio (ignora errore se già impostato)
pactl set-card-profile alsa_card.pci-0000_01_00.1 pro-audio || true

# 3) Crea il sink combinato
#    Nota: niente spazi attorno a '=' e usa virgole per separare gli slave
pactl load-module module-combine-sink \
    sink_name=CombinedStereo \
    slaves=alsa_output.pci-0000_01_00.1.pro-output-7,alsa_output.pci-0000_01_00.1.pro-output-3 \
    channels=2 channel_map=front-left,front-right \
    sink_properties=device.description=Combined >/dev/null

# 4) Imposta come sink di default (opzionale)
pactl set-default-sink CombinedStereo || true

# 5) Disconnetti collegamenti indesiderati tra il monitor di CombinedStereo e l’uscita analogica integrata
#    Aggiorna i nomi delle porte se differiscono sul tuo sistema:
#    Verifica con: pw-link
pw-link --disconnect 'CombinedStereo:monitor_FL' 'alsa_output.pci-0000_00_1f.3.analog-stereo:playback_FL' || true
pw-link --disconnect 'CombinedStereo:monitor_FR' 'alsa_output.pci-0000_00_1f.3.analog-stereo:playback_FR' || true

