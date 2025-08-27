module elixir::acl;

// === Imports ===

use sui::linked_table::{Self, LinkedTable};

// === Error Codes ===

const EInvalidRole: u64 = 0;
const EZeroAddress: u64 = 1;

// === Constants ===

const MAX_U128: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

// === Structs ===

public struct ACL has store {
    roles_by_member: LinkedTable<address, u128>
}

public struct Member has store, drop, copy {
    address: address,
    roles: u128
}

// === Functions ===

/// Create a new ACL.
public fun new(ctx: &mut TxContext): ACL {
    ACL {
        roles_by_member: linked_table::new(ctx)
    }
}

/// Check if a member has a role in the ACL.
public fun has_role(acl: &ACL, member: address, role: u8): bool {
    assert!(role < 128, EInvalidRole);

    acl.roles_by_member.contains(member) && *acl.roles_by_member.borrow(member) & (1 << role) > 0
}

/// Set all roles for a member in the ACL.
/// @param roles Roles for a member, represented as a `u128` with each bit representing the presence of (or lack of) each role.
public fun set_roles(acl: &mut ACL, member: address, roles: u128) {
    assert!(member != @0x0, EZeroAddress);

    if (acl.roles_by_member.contains(member)) {
        if (roles == 0) {
            acl.roles_by_member.remove(member);
        } else {
            *acl.roles_by_member.borrow_mut(member) = roles;
        }
    } else {
        if (roles != 0) {
            acl.roles_by_member.push_back(member, roles);
        }
    }
}

/// Add a role for a member in the ACL.
public fun add_role(acl: &mut ACL, member: address, role: u8) {
    assert!(role < 128, EInvalidRole);
    assert!(member != @0x0, EZeroAddress);

    if (acl.roles_by_member.contains(member)) {
        let roles = acl.roles_by_member.borrow_mut(member);
        *roles = *roles | (1 << role);
    } else {
        acl.roles_by_member.push_back(member, 1 << role);
    }
}

/// Revoke a role for a member in the ACL.
public fun remove_role(acl: &mut ACL, member: address, role: u8) {
    assert!(role < 128, EInvalidRole);

    if (acl.roles_by_member.contains(member)) {
        let roles = acl.roles_by_member.borrow_mut(member);
        *roles = *roles & (MAX_U128 - (1 << role));

        if (*roles == 0) {
            acl.roles_by_member.remove(member);
        }
    };
}

/// Remove all roles of member.
public fun remove_member(acl: &mut ACL, member: address) {
    if (acl.roles_by_member.contains(member)) {
        acl.roles_by_member.remove(member);
    }
}

/// Get all members.
public fun get_members(acl: &ACL): vector<Member> {
    let mut members = vector::empty<Member>();
    let mut member_opt = acl.roles_by_member.front();
    while (member_opt.is_some()) {
        let member = *member_opt.borrow();
        members.push_back(Member{
            address: member,
            roles : *acl.roles_by_member.borrow(member),
        });
        member_opt = acl.roles_by_member.next(member);
    };
    members
}

/// Get the roles of member.
public fun get_roles(acl: &ACL, member: address): u128 {
    if (acl.roles_by_member.contains(member)) {
        *acl.roles_by_member.borrow(member)
    } else {
        0
    }
}

// === Tests ===

#[test_only]
public fun contains_member_for_test(acl: &ACL, member: address): bool {
    acl.roles_by_member.contains(member)
}