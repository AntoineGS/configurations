# Reproducible Arch Installation

This guide uses the official Arch ISO and the repository's portable
`user_configuration.json` for the package, service, locale, hostname, and
bootloader choices that can be shared safely.

## ISO Workflow

1. Boot the official Arch ISO in UEFI mode.
2. Confirm that the ISO provides Archinstall 4.4.x before starting.
3. Fetch or mount this repository, enter `Linux/install/archinstall`, and run:

   ```bash
   archinstall --config user_configuration.json
   ```

4. Select exactly one target disk.
5. Choose the default disk layout, Btrfs, compression, and the default
   subvolumes: `@`, `@home`, `@log`, and `@pkg`.
6. Confirm Limine as the bootloader and disable UKI.
7. Choose or copy the ISO networking configuration so `systemd-networkd` and
   `iwd` work after reboot.
8. Create user `antoinegs` with sudo privileges. Do not save credentials in
   this repository.
9. Review the generated configuration and the destructive disk summary before
   installing.
10. Reboot, clone this repository to `~/gits/configurations`, and run
    `Linux/install/bootstrap`.

The JSON intentionally does not automate disk choice or the Btrfs layout. A
portable disk configuration cannot safely encode both choices across machines,
so they must be reviewed interactively for the selected target disk.

## References

- [Arch ISO](https://archlinux.org/download/)
- [Archinstall 4.4 release](https://github.com/archlinux/archinstall/releases/tag/v4.4.0)
- [Archinstall manual](https://archinstall.archlinux.page/)
- [Limine](https://limine-bootloader.org/)
- [Btrfs on the Arch Wiki](https://wiki.archlinux.org/title/Btrfs)
