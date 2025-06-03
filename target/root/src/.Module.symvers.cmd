cmd_/src/Module.symvers := sed 's/ko$$/o/' /src/modules.order | scripts/mod/modpost -m    -o /src/Module.symvers -e -i Module.symvers   -T -
