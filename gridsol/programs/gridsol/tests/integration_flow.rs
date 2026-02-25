use std::{path::PathBuf, str::FromStr};

use borsh::{from_slice, to_vec};
use gridsol::{
    instruction::{
        CancelOrderParams, CreateGridParams, FillOrderParams, FillOrdersParams, FillTarget, GridInstruction,
        StrategyParam,
    },
    state::Grid,
};
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    entrypoint::ProgramResult,
    instruction::{AccountMeta, Instruction},
    program_error::ProgramError,
    pubkey::Pubkey,
};
use solana_program_test::{processor, ProgramTest, ProgramTestContext};
use solana_sdk::{
    account::Account,
    signature::{Keypair, Signer},
    system_program,
    transaction::Transaction,
};

const TOKEN_TRANSFER_IX: u8 = 3;

fn spl_token_program_id() -> Pubkey {
    Pubkey::from_str("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").expect("valid")
}

fn spl_token_2022_program_id() -> Pubkey {
    Pubkey::from_str("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb").expect("valid")
}

fn bpf_out_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("programs")
        .parent()
        .expect("gridsol workspace")
        .join("target")
        .join("deploy")
}

fn add_user_account(pt: &mut ProgramTest, key: Pubkey) {
    pt.add_account(
        key,
        Account {
            lamports: 10_000_000_000,
            data: vec![],
            owner: system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
}

fn add_program_state_account(pt: &mut ProgramTest, key: Pubkey, program_id: Pubkey, data_len: usize) {
    pt.add_account(
        key,
        Account {
            lamports: 10_000_000_000,
            data: vec![0u8; data_len],
            owner: program_id,
            executable: false,
            rent_epoch: 0,
        },
    );
}

fn add_token_account(pt: &mut ProgramTest, key: Pubkey, token_program: Pubkey, amount: u64) {
    let mut data = vec![0u8; 8];
    data[..8].copy_from_slice(&amount.to_le_bytes());
    pt.add_account(
        key,
        Account {
            lamports: 1_000_000_000,
            data,
            owner: token_program,
            executable: false,
            rent_epoch: 0,
        },
    );
}

fn token_processor(program_id: &Pubkey, accounts: &[AccountInfo], data: &[u8]) -> ProgramResult {
    if data.len() != 9 || data[0] != TOKEN_TRANSFER_IX {
        return Err(ProgramError::InvalidInstructionData);
    }
    let amount =
        u64::from_le_bytes(data[1..9].try_into().map_err(|_| ProgramError::InvalidInstructionData)?);

    let mut it = accounts.iter();
    let src = next_account_info(&mut it)?;
    let dst = next_account_info(&mut it)?;
    let auth = next_account_info(&mut it)?;

    if !auth.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }
    if src.owner != program_id || dst.owner != program_id {
        return Err(ProgramError::IncorrectProgramId);
    }

    let mut src_data = src.try_borrow_mut_data()?;
    let mut dst_data = dst.try_borrow_mut_data()?;
    let src_bal = u64::from_le_bytes(src_data[..8].try_into().map_err(|_| ProgramError::InvalidAccountData)?);
    let dst_bal = u64::from_le_bytes(dst_data[..8].try_into().map_err(|_| ProgramError::InvalidAccountData)?);

    let new_src = src_bal.checked_sub(amount).ok_or(ProgramError::InsufficientFunds)?;
    let new_dst = dst_bal.checked_add(amount).ok_or(ProgramError::ArithmeticOverflow)?;
    src_data[..8].copy_from_slice(&new_src.to_le_bytes());
    dst_data[..8].copy_from_slice(&new_dst.to_le_bytes());
    Ok(())
}

fn build_program_test(program_id: Pubkey, token_program: Pubkey) -> ProgramTest {
    let mut pt = ProgramTest::default();
    // SAFETY: test setup runs single-threaded for this process context.
    unsafe {
        std::env::set_var("BPF_OUT_DIR", bpf_out_dir());
    }
    pt.prefer_bpf(true);
    pt.add_program("gridsol", program_id, None);
    pt.add_program("mock-token", token_program, processor!(token_processor));
    pt
}

fn ix(program_id: Pubkey, accounts: Vec<AccountMeta>, data: GridInstruction) -> Instruction {
    Instruction {
        program_id,
        accounts,
        data: to_vec(&data).expect("serialize"),
    }
}

async fn send_ix(ctx: &mut ProgramTestContext, signer_keys: &[&Keypair], ixs: Vec<Instruction>) {
    let recent = ctx.banks_client.get_latest_blockhash().await.expect("blockhash");
    let mut all = vec![&ctx.payer];
    all.extend_from_slice(signer_keys);
    let tx = Transaction::new_signed_with_payer(&ixs, Some(&ctx.payer.pubkey()), &all, recent);
    ctx.banks_client.process_transaction(tx).await.expect("tx success");
}

async fn send_ix_err(
    ctx: &mut ProgramTestContext,
    signer_keys: &[&Keypair],
    ixs: Vec<Instruction>,
) {
    let recent = ctx.banks_client.get_latest_blockhash().await.expect("blockhash");
    let mut all = vec![&ctx.payer];
    all.extend_from_slice(signer_keys);
    let tx = Transaction::new_signed_with_payer(&ixs, Some(&ctx.payer.pubkey()), &all, recent);
    assert!(ctx.banks_client.process_transaction(tx).await.is_err());
}

async fn token_balance(ctx: &mut ProgramTestContext, key: Pubkey) -> u64 {
    let acc = ctx
        .banks_client
        .get_account(key)
        .await
        .expect("fetch")
        .expect("exists");
    u64::from_le_bytes(acc.data[..8].try_into().expect("u64"))
}

async fn read_grid(ctx: &mut ProgramTestContext, key: Pubkey) -> Grid {
    let acc = ctx
        .banks_client
        .get_account(key)
        .await
        .expect("fetch")
        .expect("exists");
    from_slice::<Grid>(&acc.data).expect("decode grid")
}

fn grid_signer(program_id: Pubkey, owner: Pubkey, grid_id: u64) -> (Pubkey, u8) {
    Pubkey::find_program_address(&[b"grid_signer", owner.as_ref(), &grid_id.to_le_bytes()], &program_id)
}

async fn run_lifecycle(token_program: Pubkey) {
    let program_id = Pubkey::new_unique();
    let admin = Keypair::new();
    let owner = Keypair::new();
    let taker = Keypair::new();
    let config = Keypair::new();
    let grid = Keypair::new();
    let owner_base = Keypair::new();
    let owner_quote = Keypair::new();
    let admin_quote = Keypair::new();
    let taker_base = Keypair::new();
    let taker_quote = Keypair::new();
    let base_vault = Keypair::new();
    let quote_vault = Keypair::new();
    let fake_signer = Keypair::new();
    let (grid_signer_pk, signer_bump) = grid_signer(program_id, owner.pubkey(), 1);

    let mut pt = build_program_test(program_id, token_program);
    for user in [
        admin.pubkey(),
        owner.pubkey(),
        taker.pubkey(),
        grid_signer_pk,
        fake_signer.pubkey(),
    ] {
        add_user_account(&mut pt, user);
    }
    add_program_state_account(&mut pt, config.pubkey(), program_id, 512);
    add_program_state_account(&mut pt, grid.pubkey(), program_id, 20_000);
    add_token_account(&mut pt, owner_base.pubkey(), token_program, 8_000_000);
    add_token_account(&mut pt, owner_quote.pubkey(), token_program, 8_000_000);
    add_token_account(&mut pt, admin_quote.pubkey(), token_program, 0);
    add_token_account(&mut pt, taker_base.pubkey(), token_program, 0);
    add_token_account(&mut pt, taker_quote.pubkey(), token_program, 10_000_000);
    add_token_account(&mut pt, base_vault.pubkey(), token_program, 0);
    add_token_account(&mut pt, quote_vault.pubkey(), token_program, 0);

    let mut ctx = pt.start_with_context().await;

    send_ix(
        &mut ctx,
        &[&admin],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(admin.pubkey(), true),
                AccountMeta::new(config.pubkey(), false),
            ],
            GridInstruction::InitializeConfig {
                protocol_fee_bps: 1_000,
                oneshot_protocol_fee_bps: 700,
            },
        )],
    )
    .await;

    send_ix(
        &mut ctx,
        &[&owner],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(owner.pubkey(), true),
                AccountMeta::new(config.pubkey(), false),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(owner_base.pubkey(), false),
                AccountMeta::new(owner_quote.pubkey(), false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::CreateGrid(CreateGridParams {
                signer_bump,
                fee_bps: 100,
                compound: false,
                oneshot: false,
                base_amount_per_order: 1_000_000,
                ask_price0: 1_000_000_000,
                ask_count: 2,
                ask_strategy: StrategyParam::Linear { gap: 100_000_000 },
                bid_price0: 1_000_000_000,
                bid_count: 1,
                bid_strategy: StrategyParam::Linear { gap: -100_000_000 },
            }),
        )],
    )
    .await;

    assert_eq!(token_balance(&mut ctx, base_vault.pubkey()).await, 2_000_000);
    assert_eq!(token_balance(&mut ctx, quote_vault.pubkey()).await, 1_000_000);

    // fill account validation: signer mismatch must fail and not move funds
    let before_taker_quote = token_balance(&mut ctx, taker_quote.pubkey()).await;
    send_ix_err(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new_readonly(config.pubkey(), false),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(taker_base.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new_readonly(fake_signer.pubkey(), false),
            ],
            GridInstruction::FillOrder(FillOrderParams {
                side: 0,
                order_side: 0,
                order_index: 0,
                base_amount: 100_000,
            }),
        )],
    )
    .await;
    assert_eq!(token_balance(&mut ctx, taker_quote.pubkey()).await, before_taker_quote);

    // fill success
    send_ix(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new_readonly(config.pubkey(), false),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(taker_base.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::FillOrder(FillOrderParams {
                side: 0,
                order_side: 0,
                order_index: 1,
                base_amount: 1_000_000,
            }),
        )],
    )
    .await;

    let after_fill = read_grid(&mut ctx, grid.pubkey()).await;
    assert_eq!(after_fill.ask_remaining[1], 0);
    assert!(after_fill.profits_quote > 0);
    assert!(after_fill.protocol_fees_quote > 0);

    // fill_orders success on same grid, bid forward side
    send_ix(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new_readonly(config.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(taker_base.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::FillOrders(FillOrdersParams {
                fills: vec![FillTarget {
                    side: 1,
                    order_side: 1,
                    order_index: 0,
                    base_amount: 200_000,
                }],
            }),
        )],
    )
    .await;

    // cancel account validation: non-owner must fail
    send_ix_err(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(taker_base.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::CancelOrder(CancelOrderParams {
                side: 0,
                order_index: 0,
            }),
        )],
    )
    .await;

    let owner_base_before_cancel = token_balance(&mut ctx, owner_base.pubkey()).await;
    send_ix(
        &mut ctx,
        &[&owner],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(owner.pubkey(), true),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(owner_base.pubkey(), false),
                AccountMeta::new(owner_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::CancelOrder(CancelOrderParams {
                side: 0,
                order_index: 0,
            }),
        )],
    )
    .await;
    assert_eq!(
        token_balance(&mut ctx, owner_base.pubkey()).await,
        owner_base_before_cancel + 1_000_000
    );

    // withdraw permissions: non-owner/non-admin must fail
    send_ix_err(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::WithdrawProfits { amount: 0 },
        )],
    )
    .await;
    send_ix_err(
        &mut ctx,
        &[&owner],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(owner.pubkey(), true),
                AccountMeta::new_readonly(config.pubkey(), false),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(owner_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::WithdrawProtocolFees { amount: 0 },
        )],
    )
    .await;

    let owner_quote_before = token_balance(&mut ctx, owner_quote.pubkey()).await;
    send_ix(
        &mut ctx,
        &[&owner],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(owner.pubkey(), true),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(owner_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::WithdrawProfits { amount: 0 },
        )],
    )
    .await;
    assert!(token_balance(&mut ctx, owner_quote.pubkey()).await > owner_quote_before);

    let admin_quote_before = token_balance(&mut ctx, admin_quote.pubkey()).await;
    send_ix(
        &mut ctx,
        &[&admin],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(admin.pubkey(), true),
                AccountMeta::new_readonly(config.pubkey(), false),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(admin_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::WithdrawProtocolFees { amount: 0 },
        )],
    )
    .await;
    assert!(token_balance(&mut ctx, admin_quote.pubkey()).await > admin_quote_before);

    // cancel_grid permission fail then success
    send_ix_err(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(taker_base.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::CancelGrid,
        )],
    )
    .await;

    send_ix(
        &mut ctx,
        &[&owner],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(owner.pubkey(), true),
                AccountMeta::new(grid.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(base_vault.pubkey(), false),
                AccountMeta::new(quote_vault.pubkey(), false),
                AccountMeta::new(owner_base.pubkey(), false),
                AccountMeta::new(owner_quote.pubkey(), false),
                AccountMeta::new_readonly(grid_signer_pk, false),
            ],
            GridInstruction::CancelGrid,
        )],
    )
    .await;

    let g = read_grid(&mut ctx, grid.pubkey()).await;
    assert_eq!(g.status, 1);
}

#[tokio::test]
async fn integration_lifecycle_token() {
    run_lifecycle(spl_token_program_id()).await;
}

#[tokio::test]
async fn integration_lifecycle_token_2022() {
    run_lifecycle(spl_token_2022_program_id()).await;
}

#[tokio::test]
async fn integration_cross_grid_fill_orders_atomicity() {
    let token_program = spl_token_program_id();
    let program_id = Pubkey::new_unique();
    let admin = Keypair::new();
    let owner = Keypair::new();
    let taker = Keypair::new();
    let config = Keypair::new();
    let grid1 = Keypair::new();
    let grid2 = Keypair::new();
    let owner_base = Keypair::new();
    let owner_quote = Keypair::new();
    let taker_base = Keypair::new();
    let taker_quote = Keypair::new();
    let base_vault1 = Keypair::new();
    let quote_vault1 = Keypair::new();
    let base_vault2 = Keypair::new();
    let quote_vault2 = Keypair::new();
    let (signer1, bump1) = grid_signer(program_id, owner.pubkey(), 1);
    let (signer2, bump2) = grid_signer(program_id, owner.pubkey(), 2);

    let mut pt = build_program_test(program_id, token_program);
    for k in [admin.pubkey(), owner.pubkey(), taker.pubkey(), signer1, signer2] {
        add_user_account(&mut pt, k);
    }
    for k in [config.pubkey(), grid1.pubkey(), grid2.pubkey()] {
        add_program_state_account(&mut pt, k, program_id, 20_000);
    }
    add_token_account(&mut pt, owner_base.pubkey(), token_program, 20_000_000);
    add_token_account(&mut pt, owner_quote.pubkey(), token_program, 20_000_000);
    add_token_account(&mut pt, taker_base.pubkey(), token_program, 0);
    add_token_account(&mut pt, taker_quote.pubkey(), token_program, 20_000_000);
    add_token_account(&mut pt, base_vault1.pubkey(), token_program, 0);
    add_token_account(&mut pt, quote_vault1.pubkey(), token_program, 0);
    add_token_account(&mut pt, base_vault2.pubkey(), token_program, 0);
    add_token_account(&mut pt, quote_vault2.pubkey(), token_program, 0);

    let mut ctx = pt.start_with_context().await;
    send_ix(
        &mut ctx,
        &[&admin],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(admin.pubkey(), true),
                AccountMeta::new(config.pubkey(), false),
            ],
            GridInstruction::InitializeConfig {
                protocol_fee_bps: 1_000,
                oneshot_protocol_fee_bps: 700,
            },
        )],
    )
    .await;

    for (grid_kp, base_vault, quote_vault, signer, bump) in [
        (&grid1, &base_vault1, &quote_vault1, signer1, bump1),
        (&grid2, &base_vault2, &quote_vault2, signer2, bump2),
    ] {
        send_ix(
            &mut ctx,
            &[&owner],
            vec![ix(
                program_id,
                vec![
                    AccountMeta::new_readonly(owner.pubkey(), true),
                    AccountMeta::new(config.pubkey(), false),
                    AccountMeta::new(grid_kp.pubkey(), false),
                    AccountMeta::new_readonly(token_program, false),
                    AccountMeta::new(owner_base.pubkey(), false),
                    AccountMeta::new(owner_quote.pubkey(), false),
                    AccountMeta::new(base_vault.pubkey(), false),
                    AccountMeta::new(quote_vault.pubkey(), false),
                    AccountMeta::new_readonly(signer, false),
                ],
                GridInstruction::CreateGrid(CreateGridParams {
                    signer_bump: bump,
                    fee_bps: 100,
                    compound: false,
                    oneshot: false,
                    base_amount_per_order: 1_000_000,
                    ask_price0: 1_000_000_000,
                    ask_count: 1,
                    ask_strategy: StrategyParam::Linear { gap: 100_000_000 },
                    bid_price0: 1_000_000_000,
                    bid_count: 1,
                    bid_strategy: StrategyParam::Linear { gap: -100_000_000 },
                }),
            )],
        )
        .await;
    }

    // success path: one tx fills two targets on different grids
    send_ix(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new_readonly(config.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(taker_base.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new(grid1.pubkey(), false),
                AccountMeta::new(base_vault1.pubkey(), false),
                AccountMeta::new(quote_vault1.pubkey(), false),
                AccountMeta::new_readonly(signer1, false),
                AccountMeta::new(grid2.pubkey(), false),
                AccountMeta::new(base_vault2.pubkey(), false),
                AccountMeta::new(quote_vault2.pubkey(), false),
                AccountMeta::new_readonly(signer2, false),
            ],
            GridInstruction::FillOrders(FillOrdersParams {
                fills: vec![
                    FillTarget {
                        side: 0,
                        order_side: 0,
                        order_index: 0,
                        base_amount: 100_000,
                    },
                    FillTarget {
                        side: 0,
                        order_side: 0,
                        order_index: 0,
                        base_amount: 200_000,
                    },
                ],
            }),
        )],
    )
    .await;

    let snap1 = read_grid(&mut ctx, grid1.pubkey()).await;
    let snap2 = read_grid(&mut ctx, grid2.pubkey()).await;
    let snap_bal = token_balance(&mut ctx, taker_base.pubkey()).await;

    // partial failure: second target invalid -> whole tx rollback
    send_ix_err(
        &mut ctx,
        &[&taker],
        vec![ix(
            program_id,
            vec![
                AccountMeta::new_readonly(taker.pubkey(), true),
                AccountMeta::new_readonly(config.pubkey(), false),
                AccountMeta::new_readonly(token_program, false),
                AccountMeta::new(taker_base.pubkey(), false),
                AccountMeta::new(taker_quote.pubkey(), false),
                AccountMeta::new(grid1.pubkey(), false),
                AccountMeta::new(base_vault1.pubkey(), false),
                AccountMeta::new(quote_vault1.pubkey(), false),
                AccountMeta::new_readonly(signer1, false),
                AccountMeta::new(grid2.pubkey(), false),
                AccountMeta::new(base_vault2.pubkey(), false),
                AccountMeta::new(quote_vault2.pubkey(), false),
                AccountMeta::new_readonly(signer2, false),
            ],
            GridInstruction::FillOrders(FillOrdersParams {
                fills: vec![
                    FillTarget {
                        side: 0,
                        order_side: 0,
                        order_index: 0,
                        base_amount: 50_000,
                    },
                    FillTarget {
                        side: 0,
                        order_side: 0,
                        order_index: 9,
                        base_amount: 50_000,
                    },
                ],
            }),
        )],
    )
    .await;

    let final1 = read_grid(&mut ctx, grid1.pubkey()).await;
    let final2 = read_grid(&mut ctx, grid2.pubkey()).await;
    let final_bal = token_balance(&mut ctx, taker_base.pubkey()).await;
    assert_eq!(final1.ask_remaining, snap1.ask_remaining);
    assert_eq!(final2.ask_remaining, snap2.ask_remaining);
    assert_eq!(final_bal, snap_bal);
}
