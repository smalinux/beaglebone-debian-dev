cmd_/src/modules.order := {   echo /src/gpioctrl.ko; :; } | awk '!x[$$0]++' - > /src/modules.order
