# Makefile for GPIO Button LED kernel driver

# Module name
obj-m := gpioctrl.o

# Kernel build directory - adjust if needed
KDIR := /lib/modules/$(shell uname -r)/build

# Current directory
PWD := $(shell pwd)

# Default target
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

# Clean target
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

# Install target (optional)
install: all
	#sudo insmod gpioctrl.ko
	sudo insmod gpioctrl_1.ko

# Uninstall target (optional)
uninstall:
	sudo rmmod gpioctrl

# Show kernel messages
dmesg:
	dmesg | tail -20

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build the kernel module"
	@echo "  clean    - Clean build files"
	@echo "  install  - Insert the module into kernel"
	@echo "  uninstall- Remove the module from kernel"
	@echo "  dmesg    - Show recent kernel messages"

.PHONY: all clean install uninstall dmesg help
