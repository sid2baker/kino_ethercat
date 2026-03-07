# Rules for working with KinoEtherCAT

KinoEtherCAT provides Livebook Kino widgets for EtherCAT bus signals. It requires
an EtherCAT master already started and operational via the `ethercat` library.

The `KinoEtherCAT` module is the only entry point. Use `led/2,3` for read-only input
indicators, `switch/2,3` for write-only output toggles, and `render/2` to auto-render
all bit-width 1 signals for a slave. Both `slave` and `signal` arguments are atoms
matching names registered with the EtherCAT master. Read the module and function docs
before use — do not assume signal names or opts without checking.
