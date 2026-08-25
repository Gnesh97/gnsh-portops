# Configuration

Configure version, environment, framework provider (`qbcore`, `qbox`, `esx`,
or `standalone`), database provider, migrations, crane profiles, and feature
limits in `config/config.lua`. Development memory mode is non-durable and must
not be used for release servers. Canonical yard slots live in `config/yard.lua`;
berth coverage in `config/berths.lua`; customs sampling in `config/customs.lua`;
and equipment type policy in `config/equipment.lua`. Bootstrap validates every
yard slot, berth reference, migration path, and default cross-reference before
network handlers are enabled.
