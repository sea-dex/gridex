#[test]
fn probe_accountview_construction() {
    // compile-time probe only
    let _ = core::mem::size_of::<pinocchio::AccountView>();
}
