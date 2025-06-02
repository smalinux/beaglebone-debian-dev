cmd_/src/gpioctrl.ko := ld -r -EL -z noexecstack --no-warn-rwx-segments --build-id=sha1  -T scripts/module.lds -o /src/gpioctrl.ko /src/gpioctrl.o /src/gpioctrl.mod.o;  true
