#[test_only]
module elixir::acl_tests;

use elixir::acl;

// == Constants ==

const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;
const CHARLIE: address = @0xc4a1e;

const ROLE_0: u8 = 0;
const ROLE_1: u8 = 1;
const ROLE_2: u8 = 2;
const ROLE_127: u8 = 127;
const INVALID_ROLE: u8 = 128;

#[test]
fun test_new_acl() {
    let mut ctx = tx_context::dummy();
    
    let acl = acl::new(&mut ctx);
    
    // New ACL should have no members
    let members = acl::get_members(&acl);
    assert!(members.length() == 0, 0);
    
    // Check that no address has any roles
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 1);
    assert!(acl::get_roles(&acl, ALICE) == 0, 2);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_add_single_role() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add role 0 to ALICE
    acl::add_role(&mut acl, ALICE, ROLE_0);
    
    // Verify ALICE has role 0
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::get_roles(&acl, ALICE) == 1, 2); // 2^0 = 1
    
    // Verify other addresses don't have the role
    assert!(!acl::has_role(&acl, BOB, ROLE_0), 3);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_add_multiple_roles_same_member() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add multiple roles to ALICE
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_1);
    acl::add_role(&mut acl, ALICE, ROLE_2);
    
    // Verify ALICE has all roles
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::has_role(&acl, ALICE, ROLE_2), 2);
    assert!(acl::get_roles(&acl, ALICE) == 7, 3); // 2^0 + 2^1 + 2^2 = 1 + 2 + 4 = 7
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_add_same_role_twice() {
    let mut ctx = tx_context::dummy();
    let mut acl = acl::new(&mut ctx);
    
    // Add role 0 to ALICE twice
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_0);
    
    // Should still only have role 0
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(acl::get_roles(&acl, ALICE) == 1, 1); // Should still be 1, not 2
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_add_role_multiple_members() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add same role to multiple members
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, BOB, ROLE_0);
    acl::add_role(&mut acl, CHARLIE, ROLE_1);
    
    // Verify each member has their role
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(acl::has_role(&acl, BOB, ROLE_0), 1);
    assert!(acl::has_role(&acl, CHARLIE, ROLE_1), 2);
    
    // Verify cross-checks
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 3);
    assert!(!acl::has_role(&acl, BOB, ROLE_1), 4);
    assert!(!acl::has_role(&acl, CHARLIE, ROLE_0), 5);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_remove_role() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add multiple roles to ALICE
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_1);
    acl::add_role(&mut acl, ALICE, ROLE_2);
    
    // Remove role 1
    acl::remove_role(&mut acl, ALICE, ROLE_1);
    
    // Verify role 1 is removed but others remain
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::has_role(&acl, ALICE, ROLE_2), 2);
    assert!(acl::get_roles(&acl, ALICE) == 5, 3); // 2^0 + 2^2 = 1 + 4 = 5
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_remove_role_not_assigned() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add role 0 to ALICE
    acl::add_role(&mut acl, ALICE, ROLE_0);
    
    // Remove role 1 (which ALICE doesn't have)
    acl::remove_role(&mut acl, ALICE, ROLE_1);
    
    // Should still have role 0
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::get_roles(&acl, ALICE) == 1, 2);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_remove_role_nonexistent_member() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Try to remove role from member that doesn't exist
    acl::remove_role(&mut acl, ALICE, ROLE_0);
    
    // Should not crash and ALICE should still not exist
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(acl::get_roles(&acl, ALICE) == 0, 1);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_set_roles() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Set roles directly using bit mask
    let roles_mask = 13; // Binary: 1101 = roles 0, 2, 3
    acl::set_roles(&mut acl, ALICE, roles_mask);
    
    // Verify the roles
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::has_role(&acl, ALICE, ROLE_2), 2);
    assert!(acl::has_role(&acl, ALICE, 3), 3);
    assert!(acl::get_roles(&acl, ALICE) == roles_mask, 4);
    
    sui::test_utils::destroy(acl);
}


#[test]
#[expected_failure(abort_code = acl::EZeroAddress)]
fun test_set_roles_zero_address() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Set roles directly using bit mask
    let roles_mask = 13; // Binary: 1101 = roles 0, 2, 3
    acl::set_roles(&mut acl, @0x0, roles_mask);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_set_roles_overwrite() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // First set some roles
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_1);
    assert!(acl::get_roles(&acl, ALICE) == 3, 0); // 2^0 + 2^1 = 3
    
    // Overwrite with different roles
    let new_roles = 12; // Binary: 1100 = roles 2, 3
    acl::set_roles(&mut acl, ALICE, new_roles);
    
    // Verify old roles are gone and new ones are set
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 1);
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 2);
    assert!(acl::has_role(&acl, ALICE, ROLE_2), 3);
    assert!(acl::has_role(&acl, ALICE, 3), 4);
    assert!(acl::get_roles(&acl, ALICE) == new_roles, 5);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_set_roles_zero() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add some roles first
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_1);
    
    // Set roles to 0 (remove all roles)
    acl::set_roles(&mut acl, ALICE, 0);
    
    // Verify no roles remain
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::get_roles(&acl, ALICE) == 0, 2);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_remove_member() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add roles to multiple members
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_1);
    acl::add_role(&mut acl, BOB, ROLE_2);
    
    // Remove ALICE
    acl::remove_member(&mut acl, ALICE);
    
    // Verify ALICE is completely removed
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::get_roles(&acl, ALICE) == 0, 2);
    
    // Verify BOB is unaffected
    assert!(acl::has_role(&acl, BOB, ROLE_2), 3);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_remove_nonexistent_member() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Try to remove member that doesn't exist
    acl::remove_member(&mut acl, ALICE);
    
    // Should not crash
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 0);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_get_members_empty() {
    let mut ctx = tx_context::dummy();
    
    let acl = acl::new(&mut ctx);
    
    let members = acl::get_members(&acl);
    assert!(members.length() == 0, 0);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_get_members_single() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add roles to ALICE
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_2);
    
    let members = acl::get_members(&acl);
    assert!(members.length() == 1, 0);
    
    // We can't access Member fields directly due to visibility, 
    // but we can verify the member count and roles through ACL functions
    assert!(acl::get_roles(&acl, ALICE) == 5, 1); // 2^0 + 2^2 = 1 + 4 = 5
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_get_members_multiple() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add roles to multiple members
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, BOB, ROLE_1);
    acl::add_role(&mut acl, CHARLIE, ROLE_2);
    
    let members = acl::get_members(&acl);
    assert!(members.length() == 3, 0);
    
    // Verify roles for each member
    assert!(acl::get_roles(&acl, ALICE) == 1, 1); // Role 0
    assert!(acl::get_roles(&acl, BOB) == 2, 2); // Role 1
    assert!(acl::get_roles(&acl, CHARLIE) == 4, 3); // Role 2
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_boundary_roles() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Test with role 127 (maximum valid role)
    acl::add_role(&mut acl, ALICE, ROLE_127);
    assert!(acl::has_role(&acl, ALICE, ROLE_127), 0);
    
    // Test with role 0 (minimum valid role)
    acl::add_role(&mut acl, BOB, ROLE_0);
    assert!(acl::has_role(&acl, BOB, ROLE_0), 1);
    
    sui::test_utils::destroy(acl);
}

#[test]
#[expected_failure(abort_code = acl::EInvalidRole)]
fun test_add_invalid_role() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Try to add role 128 (invalid)
    acl::add_role(&mut acl, ALICE, INVALID_ROLE);
    
    sui::test_utils::destroy(acl);
}

#[test]
#[expected_failure(abort_code = acl::EInvalidRole)]
fun test_remove_invalid_role() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Try to remove role 128 (invalid)
    acl::remove_role(&mut acl, ALICE, INVALID_ROLE);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_max_roles_bitmask() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Test with maximum possible roles (all 128 roles)
    let max_roles = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // All bits set
    acl::set_roles(&mut acl, ALICE, max_roles);
    
    assert!(acl::get_roles(&acl, ALICE) == max_roles, 0);
    
    // Test some specific roles
    assert!(acl::has_role(&acl, ALICE, ROLE_0), 1);
    assert!(acl::has_role(&acl, ALICE, ROLE_127), 2);
    assert!(acl::has_role(&acl, ALICE, 64), 3); // Middle role
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_complex_role_operations() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Complex scenario: multiple operations on multiple members
    
    // Setup initial state
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_1);
    acl::add_role(&mut acl, BOB, ROLE_1);
    acl::add_role(&mut acl, BOB, ROLE_2);
    
    // Modify roles
    acl::remove_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_2);
    acl::set_roles(&mut acl, BOB, 1); // Only role 0
    
    // Verify final state
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(acl::has_role(&acl, ALICE, ROLE_1), 1);
    assert!(acl::has_role(&acl, ALICE, ROLE_2), 2);
    assert!(acl::get_roles(&acl, ALICE) == 6, 3); // 2^1 + 2^2 = 2 + 4 = 6
    
    assert!(acl::has_role(&acl, BOB, ROLE_0), 4);
    assert!(!acl::has_role(&acl, BOB, ROLE_1), 5);
    assert!(!acl::has_role(&acl, BOB, ROLE_2), 6);
    assert!(acl::get_roles(&acl, BOB) == 1, 7);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_member_lifecycle() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Add member -> modify roles -> remove member -> re-add member
    
    // Add member with roles
    acl::add_role(&mut acl, ALICE, ROLE_0);
    acl::add_role(&mut acl, ALICE, ROLE_1);
    assert!(acl::get_roles(&acl, ALICE) == 3, 0);
    
    // Remove member completely
    acl::remove_member(&mut acl, ALICE);
    assert!(acl::get_roles(&acl, ALICE) == 0, 1);
    
    // Re-add member with different roles
    acl::add_role(&mut acl, ALICE, ROLE_2);
    assert!(acl::get_roles(&acl, ALICE) == 4, 2); // Only role 2
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 3); // Previous roles gone
    assert!(!acl::has_role(&acl, ALICE, ROLE_1), 4);
    
    sui::test_utils::destroy(acl);
}

#[test]
#[expected_failure(abort_code = acl::EZeroAddress)]
fun test_zero_address() {
    let mut ctx = tx_context::dummy();
    
    let mut acl = acl::new(&mut ctx);
    
    // Test with zero address
    let zero_addr = @0x0;
    acl::add_role(&mut acl, zero_addr, ROLE_0);
    
    assert!(acl::has_role(&acl, zero_addr, ROLE_0), 0);
    assert!(acl::get_roles(&acl, zero_addr) == 1, 1);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_get_roles_nonexistent_member() {
    let mut ctx = tx_context::dummy();
    
    let acl = acl::new(&mut ctx);
    
    // Get roles for member that doesn't exist
    assert!(acl::get_roles(&acl, ALICE) == 0, 0);
    assert!(acl::get_roles(&acl, BOB) == 0, 1);
    
    sui::test_utils::destroy(acl);
}

#[test]
fun test_has_role_nonexistent_member() {
    let mut ctx = tx_context::dummy();
    
    let acl = acl::new(&mut ctx);
    
    // Check role for member that doesn't exist
    assert!(!acl::has_role(&acl, ALICE, ROLE_0), 0);
    assert!(!acl::has_role(&acl, ALICE, ROLE_127), 1);
    
    sui::test_utils::destroy(acl);
}

