#[test_only]
module elixir::init_module_tests;

use elixir::package_version::PackageVersion;
use elixir::admin_cap::AdminCap;
use elixir::deusd::{Config as DeusdConfig};
use sui::test_scenario;

#[test]
fun test_init_modules_success() {
    let mut ts = test_scenario::begin(@elixir);

    elixir::admin_cap::init_for_test(ts.ctx());
    elixir::package_version::init_for_test(ts.ctx());
    elixir::deusd::init_for_test(ts.ctx());

    ts.next_tx(@admin);
    let admin_cap: AdminCap = ts.take_from_address(@admin);

    ts.next_tx(@elixir);
    let package_version: PackageVersion = ts.take_shared();
    let deusd_config: DeusdConfig = ts.take_shared();


    test_scenario::return_to_address(@admin, admin_cap);
    test_scenario::return_shared(package_version);
    test_scenario::return_shared(deusd_config);
    ts.end();
}

