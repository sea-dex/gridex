use borsh::{BorshDeserialize, BorshSerialize};
use pinocchio::{
    cpi::{self, Seed, Signer},
    error::ProgramError,
    instruction::{InstructionAccount, InstructionView},
    AccountView, Address, ProgramResult,
};

use crate::constants::{BPS_DENOMINATOR, MAX_FEE_BPS, MAX_ORDERS_PER_SIDE, PRICE_SCALE};
use crate::error::GridError;
use crate::instruction::{
    CancelOrderParams, CreateGridParams, FillOrderParams, FillOrdersParams, FillTarget, GridInstruction, StrategyParam,
};
use crate::state::{split_fee, Config, Grid};

const GRID_SIGNER_SEED_PREFIX: &[u8] = b"grid_signer";
const TOKEN_TRANSFER_IX: u8 = 3; // spl-token TokenInstruction::Transfer
const SPL_TOKEN_PROGRAM_ID: [u8; 32] = [
    6, 221, 246, 225, 215, 101, 161, 147, 217, 203, 225, 70, 206, 235, 121, 172, 28, 180, 133, 237, 95, 91, 55,
    145, 58, 140, 245, 133, 126, 255, 0, 169,
];
const SPL_TOKEN_2022_PROGRAM_ID: [u8; 32] = [
    6, 221, 246, 225, 238, 117, 143, 222, 24, 66, 93, 188, 228, 108, 205, 218, 182, 26, 252, 77, 131, 185, 13,
    39, 254, 189, 249, 40, 216, 161, 139, 252,
];

pub fn process_instruction(
    program_id: &Address,
    accounts: &[AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    let ix = GridInstruction::try_from_slice(instruction_data).map_err(|_| GridError::InvalidInstruction)?;

    match ix {
        GridInstruction::InitializeConfig {
            protocol_fee_bps,
            oneshot_protocol_fee_bps,
        } => initialize_config(program_id, accounts, protocol_fee_bps, oneshot_protocol_fee_bps),
        GridInstruction::SetPause { paused } => set_pause(program_id, accounts, paused),
        GridInstruction::SetProtocolFee { protocol_fee_bps } => set_protocol_fee(program_id, accounts, protocol_fee_bps),
        GridInstruction::SetOneshotProtocolFee {
            oneshot_protocol_fee_bps,
        } => set_oneshot_protocol_fee(program_id, accounts, oneshot_protocol_fee_bps),
        GridInstruction::CreateGrid(params) => create_grid(program_id, accounts, params),
        GridInstruction::FillOrder(params) => fill_order(program_id, accounts, params),
        GridInstruction::FillOrders(params) => fill_orders(program_id, accounts, params),
        GridInstruction::CancelOrder(params) => cancel_order(program_id, accounts, params),
        GridInstruction::CancelGrid => cancel_grid(program_id, accounts),
        GridInstruction::WithdrawProfits { amount } => withdraw_profits(program_id, accounts, amount),
        GridInstruction::WithdrawProtocolFees { amount } => withdraw_protocol_fees(program_id, accounts, amount),
    }
}

fn next_account<'a>(it: &mut core::slice::Iter<'a, AccountView>) -> Result<&'a AccountView, ProgramError> {
    it.next().ok_or(GridError::InvalidInstruction.into())
}

fn assert_program_owned(program_id: &Address, ai: &AccountView) -> ProgramResult {
    if !ai.owned_by(program_id) {
        return Err(GridError::InvalidAccountOwner.into());
    }
    Ok(())
}

fn assert_address_matches(ai: &AccountView, expected: &[u8; 32]) -> ProgramResult {
    if ai.address().as_array() != expected {
        return Err(GridError::InvalidInstruction.into());
    }
    Ok(())
}

fn assert_token_program(token_program: &AccountView) -> ProgramResult {
    let pid = token_program.address().to_bytes();
    if pid != SPL_TOKEN_PROGRAM_ID && pid != SPL_TOKEN_2022_PROGRAM_ID {
        return Err(GridError::InvalidTokenProgram.into());
    }
    Ok(())
}

fn assert_token_account(token_program: &AccountView, ai: &AccountView) -> ProgramResult {
    if !ai.owned_by(token_program.address()) {
        return Err(GridError::InvalidTokenAccount.into());
    }
    Ok(())
}

fn read_state<T: BorshDeserialize>(ai: &AccountView) -> Result<T, ProgramError> {
    let data = ai.try_borrow()?;
    T::try_from_slice(&data).map_err(|_| GridError::InvalidInstruction.into())
}

fn write_state<T: BorshSerialize>(ai: &AccountView, state: &T) -> ProgramResult {
    let mut data = ai.try_borrow_mut()?;
    let out = borsh::to_vec(state).map_err(|_| GridError::InvalidInstruction)?;
    if out.len() > data.len() {
        return Err(GridError::AccountDataTooSmall.into());
    }

    data[..out.len()].copy_from_slice(&out);
    for b in data[out.len()..].iter_mut() {
        *b = 0;
    }
    Ok(())
}

fn u128_to_u64(v: u128) -> Result<u64, ProgramError> {
    u64::try_from(v).map_err(|_| GridError::MathOverflow.into())
}

fn mul_div_u64(a: u64, b: u64, denom: u64) -> Result<u64, ProgramError> {
    if denom == 0 {
        return Err(GridError::MathOverflow.into());
    }
    let n = (a as u128)
        .checked_mul(b as u128)
        .ok_or(GridError::MathOverflow)?;
    let q = n.checked_div(denom as u128).ok_or(GridError::MathOverflow)?;
    u128_to_u64(q)
}

fn calc_fee_u64(amount: u64, fee_bps: u16) -> Result<u64, ProgramError> {
    let n = (amount as u128)
        .checked_mul(fee_bps as u128)
        .ok_or(GridError::MathOverflow)?;
    let q = n
        .checked_div(BPS_DENOMINATOR as u128)
        .ok_or(GridError::MathOverflow)?;
    u128_to_u64(q)
}

fn sum_u64_slice(values: &[u64]) -> Result<u64, ProgramError> {
    values
        .iter()
        .try_fold(0u64, |acc, x| acc.checked_add(*x).ok_or(GridError::MathOverflow.into()))
}

fn build_side_prices(
    price0: u64,
    count: u8,
    strategy: &StrategyParam,
    is_ask: bool,
) -> Result<Vec<u64>, ProgramError> {
    let n = count as usize;
    if n == 0 {
        return Ok(Vec::new());
    }
    if n > MAX_ORDERS_PER_SIDE || price0 == 0 {
        return Err(GridError::InvalidOrderCount.into());
    }

    let mut out = Vec::with_capacity(n);
    out.push(price0);

    for i in 1..n {
        let prev = out[i - 1];
        let next = match strategy {
            StrategyParam::Linear { gap } => {
                if (is_ask && *gap <= 0) || (!is_ask && *gap >= 0) {
                    return Err(GridError::InvalidOrderCount.into());
                }

                let step = i128::from(*gap)
                    .checked_mul(i as i128)
                    .ok_or(GridError::MathOverflow)?;
                let price_i = i128::from(price0)
                    .checked_add(step)
                    .ok_or(GridError::MathOverflow)?;
                if price_i <= 0 {
                    return Err(GridError::InvalidOrderCount.into());
                }
                u64::try_from(price_i).map_err(|_| GridError::MathOverflow)?
            }
            StrategyParam::Geometry { ratio_x1e9 } => {
                if (is_ask && *ratio_x1e9 <= PRICE_SCALE)
                    || (!is_ask && (*ratio_x1e9 >= PRICE_SCALE || *ratio_x1e9 == 0))
                {
                    return Err(GridError::InvalidOrderCount.into());
                }
                mul_div_u64(prev, *ratio_x1e9, PRICE_SCALE)?
            }
        };

        if next == 0 {
            return Err(GridError::InvalidOrderCount.into());
        }
        if (is_ask && next <= prev) || (!is_ask && next >= prev) {
            return Err(GridError::InvalidOrderCount.into());
        }
        out.push(next);
    }

    Ok(out)
}

fn build_side_reverse_prices(
    price0: u64,
    count: u8,
    strategy: &StrategyParam,
    is_ask: bool,
    side_prices: &[u64],
) -> Result<Vec<u64>, ProgramError> {
    let n = count as usize;
    if n == 0 {
        return Ok(Vec::new());
    }
    if side_prices.len() != n {
        return Err(GridError::InvalidOrderCount.into());
    }

    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let rp = match strategy {
            StrategyParam::Linear { gap } => {
                if (is_ask && *gap <= 0) || (!is_ask && *gap >= 0) {
                    return Err(GridError::InvalidOrderCount.into());
                }
                if i == 0 {
                    let v = i128::from(price0)
                        .checked_sub(i128::from(*gap))
                        .ok_or(GridError::MathOverflow)?;
                    if v <= 0 {
                        return Err(GridError::InvalidOrderCount.into());
                    }
                    u64::try_from(v).map_err(|_| GridError::MathOverflow)?
                } else {
                    side_prices[i - 1]
                }
            }
            StrategyParam::Geometry { ratio_x1e9 } => {
                if *ratio_x1e9 == 0 {
                    return Err(GridError::InvalidOrderCount.into());
                }
                if i == 0 {
                    mul_div_u64(price0, PRICE_SCALE, *ratio_x1e9)?
                } else {
                    side_prices[i - 1]
                }
            }
        };
        if rp == 0 {
            return Err(GridError::InvalidOrderCount.into());
        }
        out.push(rp);
    }
    Ok(out)
}

fn token_transfer(
    token_program: &AccountView,
    source: &AccountView,
    destination: &AccountView,
    authority: &AccountView,
    amount: u64,
) -> ProgramResult {
    let mut data = [0u8; 9];
    data[0] = TOKEN_TRANSFER_IX;
    data[1..].copy_from_slice(&amount.to_le_bytes());

    let metas = [
        InstructionAccount::writable(source.address()),
        InstructionAccount::writable(destination.address()),
        InstructionAccount::readonly_signer(authority.address()),
    ];

    let ix = InstructionView {
        program_id: token_program.address(),
        accounts: &metas,
        data: &data,
    };

    let views = [source, destination, authority];
    cpi::invoke(&ix, &views)
}

fn token_transfer_signed(
    token_program: &AccountView,
    source: &AccountView,
    destination: &AccountView,
    authority: &AccountView,
    amount: u64,
    signer_seed_1: &[u8],
    signer_seed_2: &[u8],
    signer_bump: u8,
) -> ProgramResult {
    let mut data = [0u8; 9];
    data[0] = TOKEN_TRANSFER_IX;
    data[1..].copy_from_slice(&amount.to_le_bytes());

    let metas = [
        InstructionAccount::writable(source.address()),
        InstructionAccount::writable(destination.address()),
        InstructionAccount::readonly_signer(authority.address()),
    ];

    let ix = InstructionView {
        program_id: token_program.address(),
        accounts: &metas,
        data: &data,
    };

    let bump_seed = [signer_bump];
    let signer_seeds = [
        Seed::from(GRID_SIGNER_SEED_PREFIX),
        Seed::from(signer_seed_1),
        Seed::from(signer_seed_2),
        Seed::from(&bump_seed),
    ];
    let signer = Signer::from(&signer_seeds);
    let signers = [signer];

    let views = [source, destination, authority];
    cpi::invoke_signed_with_bounds::<3>(&ix, &views, &signers)
}

fn apply_ask_bookkeeping(
    grid: &mut Grid,
    idx: usize,
    fill_base: u64,
    quote_gross: u64,
    maker_fee: u64,
    quota_price: u64,
) -> ProgramResult {
    let remaining = grid.ask_remaining[idx];
    grid.ask_remaining[idx] = remaining.checked_sub(fill_base).ok_or(GridError::MathOverflow)?;

    if grid.compound {
        let add_rev = quote_gross.checked_add(maker_fee).ok_or(GridError::MathOverflow)?;
        grid.ask_reverse_quote[idx] = grid.ask_reverse_quote[idx]
            .checked_add(add_rev)
            .ok_or(GridError::MathOverflow)?;
        return Ok(());
    }

    // Non-compound follows GridEx behavior: cap reverse quote at one-order quota,
    // and push overflow to profits.
    let target_quote = mul_div_u64(grid.base_amount_per_order, quota_price, PRICE_SCALE)?;
    let add_rev = quote_gross.checked_add(maker_fee).ok_or(GridError::MathOverflow)?;
    let cur_rev = grid.ask_reverse_quote[idx];

    if cur_rev >= target_quote {
        grid.profits_quote = grid
            .profits_quote
            .checked_add(add_rev)
            .ok_or(GridError::MathOverflow)?;
        return Ok(());
    }

    let next_rev = cur_rev.checked_add(add_rev).ok_or(GridError::MathOverflow)?;
    if next_rev > target_quote {
        let overflow = next_rev.checked_sub(target_quote).ok_or(GridError::MathOverflow)?;
        grid.ask_reverse_quote[idx] = target_quote;
        grid.profits_quote = grid
            .profits_quote
            .checked_add(overflow)
            .ok_or(GridError::MathOverflow)?;
    } else {
        grid.ask_reverse_quote[idx] = next_rev;
    }

    Ok(())
}

fn apply_bid_bookkeeping(
    grid: &mut Grid,
    idx: usize,
    fill_base: u64,
    quote_gross: u64,
    maker_fee: u64,
) -> ProgramResult {
    let quote_decrease = if grid.compound {
        quote_gross.checked_sub(maker_fee).ok_or(GridError::MathOverflow)?
    } else {
        quote_gross
    };

    let remaining_quote = grid.bid_remaining_quote[idx];
    grid.bid_remaining_quote[idx] = remaining_quote
        .checked_sub(quote_decrease)
        .ok_or(GridError::MathOverflow)?;
    grid.bid_reverse_base[idx] = grid.bid_reverse_base[idx]
        .checked_add(fill_base)
        .ok_or(GridError::MathOverflow)?;

    if !grid.compound {
        grid.profits_quote = grid
            .profits_quote
            .checked_add(maker_fee)
            .ok_or(GridError::MathOverflow)?;
    }

    Ok(())
}

fn apply_bid_reverse_bookkeeping(
    grid: &mut Grid,
    idx: usize,
    fill_base: u64,
    quote_gross: u64,
    maker_fee: u64,
    quota_price: u64,
) -> ProgramResult {
    grid.bid_reverse_base[idx] = grid.bid_reverse_base[idx]
        .checked_sub(fill_base)
        .ok_or(GridError::MathOverflow)?;

    let add_rev = quote_gross.checked_add(maker_fee).ok_or(GridError::MathOverflow)?;
    if grid.compound {
        grid.bid_remaining_quote[idx] = grid.bid_remaining_quote[idx]
            .checked_add(add_rev)
            .ok_or(GridError::MathOverflow)?;
        return Ok(());
    }

    let target_quote = mul_div_u64(grid.base_amount_per_order, quota_price, PRICE_SCALE)?;
    let cur = grid.bid_remaining_quote[idx];
    if cur >= target_quote {
        grid.profits_quote = grid
            .profits_quote
            .checked_add(add_rev)
            .ok_or(GridError::MathOverflow)?;
        return Ok(());
    }

    let next = cur.checked_add(add_rev).ok_or(GridError::MathOverflow)?;
    if next > target_quote {
        let overflow = next.checked_sub(target_quote).ok_or(GridError::MathOverflow)?;
        grid.bid_remaining_quote[idx] = target_quote;
        grid.profits_quote = grid
            .profits_quote
            .checked_add(overflow)
            .ok_or(GridError::MathOverflow)?;
    } else {
        grid.bid_remaining_quote[idx] = next;
    }

    Ok(())
}

fn apply_ask_reverse_bookkeeping(
    grid: &mut Grid,
    idx: usize,
    fill_base: u64,
    quote_gross: u64,
    maker_fee: u64,
) -> ProgramResult {
    let quote_decrease = if grid.compound {
        quote_gross.checked_sub(maker_fee).ok_or(GridError::MathOverflow)?
    } else {
        quote_gross
    };

    grid.ask_reverse_quote[idx] = grid.ask_reverse_quote[idx]
        .checked_sub(quote_decrease)
        .ok_or(GridError::MathOverflow)?;
    grid.ask_remaining[idx] = grid.ask_remaining[idx]
        .checked_add(fill_base)
        .ok_or(GridError::MathOverflow)?;

    if !grid.compound {
        grid.profits_quote = grid
            .profits_quote
            .checked_add(maker_fee)
            .ok_or(GridError::MathOverflow)?;
    }
    Ok(())
}

fn initialize_config(
    program_id: &Address,
    accounts: &[AccountView],
    protocol_fee_bps: u16,
    oneshot_protocol_fee_bps: u16,
) -> ProgramResult {
    if protocol_fee_bps > MAX_FEE_BPS || oneshot_protocol_fee_bps > MAX_FEE_BPS {
        return Err(GridError::InvalidFee.into());
    }

    let mut it = accounts.iter();
    let admin = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;

    if !admin.is_signer() {
        return Err(GridError::NotAdmin.into());
    }
    assert_program_owned(program_id, config_ai)?;

    let config = Config {
        admin: admin.address().to_bytes(),
        paused: false,
        protocol_fee_bps,
        oneshot_protocol_fee_bps,
        next_grid_id: 1,
    };

    write_state(config_ai, &config)
}

fn set_pause(program_id: &Address, accounts: &[AccountView], paused: bool) -> ProgramResult {
    let mut it = accounts.iter();
    let admin = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;

    if !admin.is_signer() {
        return Err(GridError::NotAdmin.into());
    }

    assert_program_owned(program_id, config_ai)?;

    let mut config: Config = read_state(config_ai)?;
    if config.admin != admin.address().to_bytes() {
        return Err(GridError::NotAdmin.into());
    }

    config.paused = paused;
    write_state(config_ai, &config)
}

fn set_protocol_fee(program_id: &Address, accounts: &[AccountView], protocol_fee_bps: u16) -> ProgramResult {
    if protocol_fee_bps > MAX_FEE_BPS {
        return Err(GridError::InvalidFee.into());
    }

    let mut it = accounts.iter();
    let admin = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;

    if !admin.is_signer() {
        return Err(GridError::NotAdmin.into());
    }

    assert_program_owned(program_id, config_ai)?;

    let mut config: Config = read_state(config_ai)?;
    if config.admin != admin.address().to_bytes() {
        return Err(GridError::NotAdmin.into());
    }

    config.protocol_fee_bps = protocol_fee_bps;
    write_state(config_ai, &config)
}

fn set_oneshot_protocol_fee(
    program_id: &Address,
    accounts: &[AccountView],
    oneshot_protocol_fee_bps: u16,
) -> ProgramResult {
    if oneshot_protocol_fee_bps > MAX_FEE_BPS {
        return Err(GridError::InvalidFee.into());
    }

    let mut it = accounts.iter();
    let admin = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;

    if !admin.is_signer() {
        return Err(GridError::NotAdmin.into());
    }

    assert_program_owned(program_id, config_ai)?;

    let mut config: Config = read_state(config_ai)?;
    if config.admin != admin.address().to_bytes() {
        return Err(GridError::NotAdmin.into());
    }

    config.oneshot_protocol_fee_bps = oneshot_protocol_fee_bps;
    write_state(config_ai, &config)
}

fn create_grid(program_id: &Address, accounts: &[AccountView], params: CreateGridParams) -> ProgramResult {
    if params.fee_bps > MAX_FEE_BPS {
        return Err(GridError::InvalidFee.into());
    }
    if params.base_amount_per_order == 0 {
        return Err(GridError::ZeroAmount.into());
    }
    if params.ask_count == 0 && params.bid_count == 0 {
        return Err(GridError::InvalidOrderCount.into());
    }
    if (params.ask_count as usize) > MAX_ORDERS_PER_SIDE || (params.bid_count as usize) > MAX_ORDERS_PER_SIDE {
        return Err(GridError::InvalidOrderCount.into());
    }

    // owner, config, grid, token_program, owner_base_ata, owner_quote_ata, base_vault, quote_vault, grid_signer
    let mut it = accounts.iter();
    let owner = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;
    let grid_ai = next_account(&mut it)?;
    let token_program = next_account(&mut it)?;
    let owner_base_ata = next_account(&mut it)?;
    let owner_quote_ata = next_account(&mut it)?;
    let base_vault = next_account(&mut it)?;
    let quote_vault = next_account(&mut it)?;
    let grid_signer = next_account(&mut it)?;
    assert_token_program(token_program)?;
    assert_token_account(token_program, owner_base_ata)?;
    assert_token_account(token_program, owner_quote_ata)?;
    assert_token_account(token_program, base_vault)?;
    assert_token_account(token_program, quote_vault)?;

    if !owner.is_signer() {
        return Err(GridError::NotGridOwner.into());
    }

    assert_program_owned(program_id, config_ai)?;
    assert_program_owned(program_id, grid_ai)?;

    let mut config: Config = read_state(config_ai)?;
    if config.paused {
        return Err(GridError::Paused.into());
    }

    let owner_bytes = owner.address().to_bytes();
    let ask_prices = build_side_prices(
        params.ask_price0,
        params.ask_count,
        &params.ask_strategy,
        true,
    )?;
    let ask_rev_prices = build_side_reverse_prices(
        params.ask_price0,
        params.ask_count,
        &params.ask_strategy,
        true,
        &ask_prices,
    )?;
    let bid_prices = build_side_prices(
        params.bid_price0,
        params.bid_count,
        &params.bid_strategy,
        false,
    )?;
    let bid_rev_prices = build_side_reverse_prices(
        params.bid_price0,
        params.bid_count,
        &params.bid_strategy,
        false,
        &bid_prices,
    )?;

    let ask_total_base = params
        .base_amount_per_order
        .checked_mul(ask_prices.len() as u64)
        .ok_or(GridError::MathOverflow)?;

    let mut bid_remaining_quote = Vec::with_capacity(bid_prices.len());
    for price in &bid_prices {
        let quote = mul_div_u64(params.base_amount_per_order, *price, PRICE_SCALE)?;
        if quote == 0 {
            return Err(GridError::InvalidOrderCount.into());
        }
        bid_remaining_quote.push(quote);
    }

    let bid_total_quote: u64 = bid_remaining_quote
        .iter()
        .try_fold(0u64, |acc, x| acc.checked_add(*x).ok_or(GridError::MathOverflow))?;
    let bid_prices_len = bid_prices.len();
    let ask_prices_len = ask_prices.len();
    let grid = Grid {
        owner: owner_bytes,
        id: config.next_grid_id,
        status: 0,
        base_vault: base_vault.address().to_bytes(),
        quote_vault: quote_vault.address().to_bytes(),
        signer: grid_signer.address().to_bytes(),
        signer_bump: params.signer_bump,
        fee_bps: if params.oneshot {
            config.oneshot_protocol_fee_bps
        } else {
            params.fee_bps
        },
        compound: params.compound,
        oneshot: params.oneshot,
        base_amount_per_order: params.base_amount_per_order,
        profits_quote: 0,
        protocol_fees_quote: 0,
        ask_prices,
        ask_rev_prices,
        ask_remaining: vec![params.base_amount_per_order; ask_prices_len],
        ask_reverse_quote: vec![0; ask_prices_len],
        bid_prices,
        bid_rev_prices,
        bid_remaining_quote,
        bid_reverse_base: vec![0; bid_prices_len],
    };

    if !grid.can_place() {
        return Err(GridError::InvalidOrderCount.into());
    }

    if ask_total_base > 0 {
        token_transfer(token_program, owner_base_ata, base_vault, owner, ask_total_base)?;
    }
    if bid_total_quote > 0 {
        token_transfer(token_program, owner_quote_ata, quote_vault, owner, bid_total_quote)?;
    }

    config.next_grid_id = config.next_grid_id.checked_add(1).ok_or(GridError::MathOverflow)?;

    write_state(config_ai, &config)?;
    write_state(grid_ai, &grid)
}

fn fill_order(program_id: &Address, accounts: &[AccountView], params: FillOrderParams) -> ProgramResult {
    if params.base_amount == 0 {
        return Err(GridError::ZeroAmount.into());
    }

    // taker, config, grid, token_program, taker_base_ata, taker_quote_ata, base_vault, quote_vault, grid_signer
    let mut it = accounts.iter();
    let taker = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;
    let grid_ai = next_account(&mut it)?;
    let token_program = next_account(&mut it)?;
    let taker_base_ata = next_account(&mut it)?;
    let taker_quote_ata = next_account(&mut it)?;
    let base_vault = next_account(&mut it)?;
    let quote_vault = next_account(&mut it)?;
    let grid_signer = next_account(&mut it)?;
    assert_token_program(token_program)?;
    assert_token_account(token_program, taker_base_ata)?;
    assert_token_account(token_program, taker_quote_ata)?;
    assert_token_account(token_program, base_vault)?;
    assert_token_account(token_program, quote_vault)?;

    if !taker.is_signer() {
        return Err(GridError::InvalidInstruction.into());
    }
    assert_program_owned(program_id, config_ai)?;
    assert_program_owned(program_id, grid_ai)?;

    let config: Config = read_state(config_ai)?;
    if config.paused {
        return Err(GridError::Paused.into());
    }

    let mut grid: Grid = read_state(grid_ai)?;
    if !grid.is_active() {
        return Err(GridError::GridCanceled.into());
    }
    assert_address_matches(base_vault, &grid.base_vault)?;
    assert_address_matches(quote_vault, &grid.quote_vault)?;
    assert_address_matches(grid_signer, &grid.signer)?;

    execute_single_fill(
        &config,
        &mut grid,
        token_program,
        taker,
        taker_base_ata,
        taker_quote_ata,
        base_vault,
        quote_vault,
        grid_signer,
        &FillTarget {
            side: params.side,
            order_side: params.order_side,
            order_index: params.order_index,
            base_amount: params.base_amount,
        },
    )?;
    write_state(grid_ai, &grid)
}

fn fill_orders(program_id: &Address, accounts: &[AccountView], params: FillOrdersParams) -> ProgramResult {
    if params.fills.is_empty() {
        return Err(GridError::InvalidOrderCount.into());
    }

    // taker, config, token_program, taker_base_ata, taker_quote_ata,
    // then for each fill: grid, base_vault, quote_vault, grid_signer
    let mut it = accounts.iter();
    let taker = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;
    let token_program = next_account(&mut it)?;
    let taker_base_ata = next_account(&mut it)?;
    let taker_quote_ata = next_account(&mut it)?;
    assert_token_program(token_program)?;
    assert_token_account(token_program, taker_base_ata)?;
    assert_token_account(token_program, taker_quote_ata)?;

    if !taker.is_signer() {
        return Err(GridError::InvalidInstruction.into());
    }
    assert_program_owned(program_id, config_ai)?;
    let config: Config = read_state(config_ai)?;
    if config.paused {
        return Err(GridError::Paused.into());
    }

    for fill in &params.fills {
        if fill.base_amount == 0 {
            return Err(GridError::ZeroAmount.into());
        }

        let grid_ai = next_account(&mut it)?;
        let base_vault = next_account(&mut it)?;
        let quote_vault = next_account(&mut it)?;
        let grid_signer = next_account(&mut it)?;
        assert_token_account(token_program, base_vault)?;
        assert_token_account(token_program, quote_vault)?;

        assert_program_owned(program_id, grid_ai)?;
        let mut grid: Grid = read_state(grid_ai)?;
        if !grid.is_active() {
            return Err(GridError::GridCanceled.into());
        }

        assert_address_matches(base_vault, &grid.base_vault)?;
        assert_address_matches(quote_vault, &grid.quote_vault)?;
        assert_address_matches(grid_signer, &grid.signer)?;

        execute_single_fill(
            &config,
            &mut grid,
            token_program,
            taker,
            taker_base_ata,
            taker_quote_ata,
            base_vault,
            quote_vault,
            grid_signer,
            fill,
        )?;
        write_state(grid_ai, &grid)?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn execute_single_fill(
    config: &Config,
    grid: &mut Grid,
    token_program: &AccountView,
    taker: &AccountView,
    taker_base_ata: &AccountView,
    taker_quote_ata: &AccountView,
    base_vault: &AccountView,
    quote_vault: &AccountView,
    grid_signer: &AccountView,
    fill: &FillTarget,
) -> ProgramResult {
    let idx = fill.order_index as usize;
    let req_base = fill.base_amount;
    let grid_id_seed = grid.id.to_le_bytes();

    let (fill_base, quote_gross, total_fee, protocol_fee) = match (fill.side, fill.order_side) {
        // fillAsk on ask order (forward)
        (0, 0) => {
            if idx >= grid.ask_remaining.len() {
                return Err(GridError::InvalidOrderIndex.into());
            }
            let remaining = grid.ask_remaining[idx];
            if remaining == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            let fill_base = remaining.min(req_base);
            let quote_gross = mul_div_u64(fill_base, grid.ask_prices[idx], PRICE_SCALE)?;
            let total_fee = calc_fee_u64(quote_gross, grid.fee_bps)?;
            let (protocol_fee, maker_fee) = split_fee(
                total_fee,
                config.protocol_fee_bps,
                config.oneshot_protocol_fee_bps,
                grid.oneshot,
            );
            apply_ask_bookkeeping(
                grid,
                idx,
                fill_base,
                quote_gross,
                maker_fee,
                grid.ask_rev_prices[idx],
            )?;
            (fill_base, quote_gross, total_fee, protocol_fee)
        }
        // fillAsk on bid order (reverse)
        (0, 1) => {
            if grid.oneshot {
                return Err(GridError::InvalidInstruction.into());
            }
            if idx >= grid.bid_reverse_base.len() {
                return Err(GridError::InvalidOrderIndex.into());
            }
            let remaining_base = grid.bid_reverse_base[idx];
            if remaining_base == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            let fill_base = remaining_base.min(req_base);
            let quote_gross = mul_div_u64(fill_base, grid.bid_rev_prices[idx], PRICE_SCALE)?;
            let total_fee = calc_fee_u64(quote_gross, grid.fee_bps)?;
            let (protocol_fee, maker_fee) = split_fee(
                total_fee,
                config.protocol_fee_bps,
                config.oneshot_protocol_fee_bps,
                grid.oneshot,
            );
            apply_bid_reverse_bookkeeping(
                grid,
                idx,
                fill_base,
                quote_gross,
                maker_fee,
                grid.bid_prices[idx],
            )?;
            (fill_base, quote_gross, total_fee, protocol_fee)
        }
        // fillBid on bid order (forward)
        (1, 1) => {
            if idx >= grid.bid_remaining_quote.len() {
                return Err(GridError::InvalidOrderIndex.into());
            }
            let remaining_quote = grid.bid_remaining_quote[idx];
            if remaining_quote == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            let price = grid.bid_prices[idx];
            let mut quote_gross = mul_div_u64(req_base, price, PRICE_SCALE)?;
            let mut fill_base = req_base;
            if quote_gross > remaining_quote {
                quote_gross = remaining_quote;
                fill_base = mul_div_u64(remaining_quote, PRICE_SCALE, price)?;
            }
            if fill_base == 0 || quote_gross == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            let total_fee = calc_fee_u64(quote_gross, grid.fee_bps)?;
            let (protocol_fee, maker_fee) = split_fee(
                total_fee,
                config.protocol_fee_bps,
                config.oneshot_protocol_fee_bps,
                grid.oneshot,
            );
            apply_bid_bookkeeping(grid, idx, fill_base, quote_gross, maker_fee)?;
            (fill_base, quote_gross, total_fee, protocol_fee)
        }
        // fillBid on ask order (reverse)
        (1, 0) => {
            if grid.oneshot {
                return Err(GridError::InvalidInstruction.into());
            }
            if idx >= grid.ask_reverse_quote.len() {
                return Err(GridError::InvalidOrderIndex.into());
            }
            let remaining_quote = grid.ask_reverse_quote[idx];
            if remaining_quote == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            let price = grid.ask_rev_prices[idx];
            let mut quote_gross = mul_div_u64(req_base, price, PRICE_SCALE)?;
            let mut fill_base = req_base;
            if quote_gross > remaining_quote {
                quote_gross = remaining_quote;
                fill_base = mul_div_u64(remaining_quote, PRICE_SCALE, price)?;
            }
            if fill_base == 0 || quote_gross == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            let total_fee = calc_fee_u64(quote_gross, grid.fee_bps)?;
            let (protocol_fee, maker_fee) = split_fee(
                total_fee,
                config.protocol_fee_bps,
                config.oneshot_protocol_fee_bps,
                grid.oneshot,
            );
            apply_ask_reverse_bookkeeping(grid, idx, fill_base, quote_gross, maker_fee)?;
            (fill_base, quote_gross, total_fee, protocol_fee)
        }
        _ => return Err(GridError::InvalidInstruction.into()),
    };

    match fill.side {
        // taker buys base, pays quote
        0 => {
            let quote_in = quote_gross.checked_add(total_fee).ok_or(GridError::MathOverflow)?;
            token_transfer(token_program, taker_quote_ata, quote_vault, taker, quote_in)?;
            token_transfer_signed(
                token_program,
                base_vault,
                taker_base_ata,
                grid_signer,
                fill_base,
                &grid.owner,
                &grid_id_seed,
                grid.signer_bump,
            )?;
        }
        // taker sells base, receives quote
        1 => {
            let quote_out = quote_gross.checked_sub(total_fee).ok_or(GridError::MathOverflow)?;
            token_transfer(token_program, taker_base_ata, base_vault, taker, fill_base)?;
            token_transfer_signed(
                token_program,
                quote_vault,
                taker_quote_ata,
                grid_signer,
                quote_out,
                &grid.owner,
                &grid_id_seed,
                grid.signer_bump,
            )?;
        }
        _ => return Err(GridError::InvalidInstruction.into()),
    }

    grid.protocol_fees_quote = grid
        .protocol_fees_quote
        .checked_add(protocol_fee)
        .ok_or(GridError::MathOverflow)?;
    Ok(())
}

fn cancel_order(program_id: &Address, accounts: &[AccountView], params: CancelOrderParams) -> ProgramResult {
    // owner, grid, token_program, base_vault, quote_vault, owner_base_ata, owner_quote_ata, grid_signer
    let mut it = accounts.iter();
    let owner = next_account(&mut it)?;
    let grid_ai = next_account(&mut it)?;
    let token_program = next_account(&mut it)?;
    let base_vault = next_account(&mut it)?;
    let quote_vault = next_account(&mut it)?;
    let owner_base_ata = next_account(&mut it)?;
    let owner_quote_ata = next_account(&mut it)?;
    let grid_signer = next_account(&mut it)?;
    assert_token_program(token_program)?;
    assert_token_account(token_program, base_vault)?;
    assert_token_account(token_program, quote_vault)?;
    assert_token_account(token_program, owner_base_ata)?;
    assert_token_account(token_program, owner_quote_ata)?;

    if !owner.is_signer() {
        return Err(GridError::NotGridOwner.into());
    }

    assert_program_owned(program_id, grid_ai)?;
    let mut grid: Grid = read_state(grid_ai)?;
    if grid.owner != owner.address().to_bytes() {
        return Err(GridError::NotGridOwner.into());
    }

    assert_address_matches(base_vault, &grid.base_vault)?;
    assert_address_matches(quote_vault, &grid.quote_vault)?;
    assert_address_matches(grid_signer, &grid.signer)?;

    let grid_id_seed = grid.id.to_le_bytes();
    match params.side {
        0 => {
            let idx = params.order_index as usize;
            if idx >= grid.ask_remaining.len() {
                return Err(GridError::InvalidOrderIndex.into());
            }
            let refund_base = grid.ask_remaining[idx];
            let refund_quote = grid.ask_reverse_quote[idx];
            if refund_base == 0 && refund_quote == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            grid.ask_remaining[idx] = 0;
            grid.ask_reverse_quote[idx] = 0;
            if refund_base > 0 {
                token_transfer_signed(
                    token_program,
                    base_vault,
                    owner_base_ata,
                    grid_signer,
                    refund_base,
                    &grid.owner,
                    &grid_id_seed,
                    grid.signer_bump,
                )?;
            }
            if refund_quote > 0 {
                token_transfer_signed(
                    token_program,
                    quote_vault,
                    owner_quote_ata,
                    grid_signer,
                    refund_quote,
                    &grid.owner,
                    &grid_id_seed,
                    grid.signer_bump,
                )?;
            }
        }
        1 => {
            let idx = params.order_index as usize;
            if idx >= grid.bid_remaining_quote.len() {
                return Err(GridError::InvalidOrderIndex.into());
            }
            let refund_base = grid.bid_reverse_base[idx];
            let refund_quote = grid.bid_remaining_quote[idx];
            if refund_base == 0 && refund_quote == 0 {
                return Err(GridError::InsufficientLiquidity.into());
            }
            grid.bid_remaining_quote[idx] = 0;
            grid.bid_reverse_base[idx] = 0;
            if refund_base > 0 {
                token_transfer_signed(
                    token_program,
                    base_vault,
                    owner_base_ata,
                    grid_signer,
                    refund_base,
                    &grid.owner,
                    &grid_id_seed,
                    grid.signer_bump,
                )?;
            }
            if refund_quote > 0 {
                token_transfer_signed(
                    token_program,
                    quote_vault,
                    owner_quote_ata,
                    grid_signer,
                    refund_quote,
                    &grid.owner,
                    &grid_id_seed,
                    grid.signer_bump,
                )?;
            }
        }
        _ => return Err(GridError::InvalidInstruction.into()),
    }

    write_state(grid_ai, &grid)
}

fn cancel_grid(program_id: &Address, accounts: &[AccountView]) -> ProgramResult {
    // owner, grid, token_program, base_vault, quote_vault, owner_base_ata, owner_quote_ata, grid_signer
    let mut it = accounts.iter();
    let owner = next_account(&mut it)?;
    let grid_ai = next_account(&mut it)?;
    let token_program = next_account(&mut it)?;
    let base_vault = next_account(&mut it)?;
    let quote_vault = next_account(&mut it)?;
    let owner_base_ata = next_account(&mut it)?;
    let owner_quote_ata = next_account(&mut it)?;
    let grid_signer = next_account(&mut it)?;
    assert_token_program(token_program)?;
    assert_token_account(token_program, base_vault)?;
    assert_token_account(token_program, quote_vault)?;
    assert_token_account(token_program, owner_base_ata)?;
    assert_token_account(token_program, owner_quote_ata)?;

    if !owner.is_signer() {
        return Err(GridError::NotGridOwner.into());
    }

    assert_program_owned(program_id, grid_ai)?;

    let mut grid: Grid = read_state(grid_ai)?;
    if grid.owner != owner.address().to_bytes() {
        return Err(GridError::NotGridOwner.into());
    }
    if !grid.is_active() {
        return Err(GridError::GridCanceled.into());
    }
    assert_address_matches(base_vault, &grid.base_vault)?;
    assert_address_matches(quote_vault, &grid.quote_vault)?;
    assert_address_matches(grid_signer, &grid.signer)?;

    let refund_base = sum_u64_slice(&grid.ask_remaining)?
        .checked_add(sum_u64_slice(&grid.bid_reverse_base)?)
        .ok_or(GridError::MathOverflow)?;
    let refund_quote = sum_u64_slice(&grid.ask_reverse_quote)?
        .checked_add(sum_u64_slice(&grid.bid_remaining_quote)?)
        .ok_or(GridError::MathOverflow)?
        .checked_add(grid.profits_quote)
        .ok_or(GridError::MathOverflow)?;

    let grid_id_seed = grid.id.to_le_bytes();
    if refund_base > 0 {
        token_transfer_signed(
            token_program,
            base_vault,
            owner_base_ata,
            grid_signer,
            refund_base,
            &grid.owner,
            &grid_id_seed,
            grid.signer_bump,
        )?;
    }
    if refund_quote > 0 {
        token_transfer_signed(
            token_program,
            quote_vault,
            owner_quote_ata,
            grid_signer,
            refund_quote,
            &grid.owner,
            &grid_id_seed,
            grid.signer_bump,
        )?;
    }

    for v in &mut grid.ask_remaining {
        *v = 0;
    }
    for v in &mut grid.ask_reverse_quote {
        *v = 0;
    }
    for v in &mut grid.bid_remaining_quote {
        *v = 0;
    }
    for v in &mut grid.bid_reverse_base {
        *v = 0;
    }
    grid.profits_quote = 0;

    grid.status = 1;
    write_state(grid_ai, &grid)
}

fn withdraw_profits(program_id: &Address, accounts: &[AccountView], amount: u64) -> ProgramResult {
    // owner, grid, token_program, quote_vault, owner_quote_ata, grid_signer
    let mut it = accounts.iter();
    let owner = next_account(&mut it)?;
    let grid_ai = next_account(&mut it)?;
    let token_program = next_account(&mut it)?;
    let quote_vault = next_account(&mut it)?;
    let owner_quote_ata = next_account(&mut it)?;
    let grid_signer = next_account(&mut it)?;
    assert_token_program(token_program)?;
    assert_token_account(token_program, quote_vault)?;
    assert_token_account(token_program, owner_quote_ata)?;

    if !owner.is_signer() {
        return Err(GridError::NotGridOwner.into());
    }

    assert_program_owned(program_id, grid_ai)?;

    let mut grid: Grid = read_state(grid_ai)?;
    if grid.owner != owner.address().to_bytes() {
        return Err(GridError::NotGridOwner.into());
    }

    assert_address_matches(quote_vault, &grid.quote_vault)?;
    assert_address_matches(grid_signer, &grid.signer)?;

    let withdraw_amt = if amount == 0 {
        grid.profits_quote
    } else {
        amount.min(grid.profits_quote)
    };

    if withdraw_amt == 0 {
        return Err(GridError::NoProfits.into());
    }

    let grid_id_seed = grid.id.to_le_bytes();
    token_transfer_signed(
        token_program,
        quote_vault,
        owner_quote_ata,
        grid_signer,
        withdraw_amt,
        &grid.owner,
        &grid_id_seed,
        grid.signer_bump,
    )?;

    grid.profits_quote = grid
        .profits_quote
        .checked_sub(withdraw_amt)
        .ok_or(GridError::MathOverflow)?;

    write_state(grid_ai, &grid)
}

fn withdraw_protocol_fees(program_id: &Address, accounts: &[AccountView], amount: u64) -> ProgramResult {
    // admin, config, grid, token_program, quote_vault, admin_quote_ata, grid_signer
    let mut it = accounts.iter();
    let admin = next_account(&mut it)?;
    let config_ai = next_account(&mut it)?;
    let grid_ai = next_account(&mut it)?;
    let token_program = next_account(&mut it)?;
    let quote_vault = next_account(&mut it)?;
    let admin_quote_ata = next_account(&mut it)?;
    let grid_signer = next_account(&mut it)?;

    if !admin.is_signer() {
        return Err(GridError::NotAdmin.into());
    }
    assert_program_owned(program_id, config_ai)?;
    assert_program_owned(program_id, grid_ai)?;
    assert_token_program(token_program)?;
    assert_token_account(token_program, quote_vault)?;
    assert_token_account(token_program, admin_quote_ata)?;

    let config: Config = read_state(config_ai)?;
    if config.admin != admin.address().to_bytes() {
        return Err(GridError::NotAdmin.into());
    }

    let mut grid: Grid = read_state(grid_ai)?;
    assert_address_matches(quote_vault, &grid.quote_vault)?;
    assert_address_matches(grid_signer, &grid.signer)?;

    let withdraw_amt = if amount == 0 {
        grid.protocol_fees_quote
    } else {
        amount.min(grid.protocol_fees_quote)
    };
    if withdraw_amt == 0 {
        return Err(GridError::NoProfits.into());
    }

    let grid_id_seed = grid.id.to_le_bytes();
    token_transfer_signed(
        token_program,
        quote_vault,
        admin_quote_ata,
        grid_signer,
        withdraw_amt,
        &grid.owner,
        &grid_id_seed,
        grid.signer_bump,
    )?;

    grid.protocol_fees_quote = grid
        .protocol_fees_quote
        .checked_sub(withdraw_amt)
        .ok_or(GridError::MathOverflow)?;

    write_state(grid_ai, &grid)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::instruction::StrategyParam;

    fn sample_grid(compound: bool) -> Grid {
        Grid {
            owner: [1u8; 32],
            id: 7,
            status: 0,
            base_vault: [2u8; 32],
            quote_vault: [3u8; 32],
            signer: [4u8; 32],
            signer_bump: 200,
            fee_bps: 100,
            compound,
            oneshot: false,
            base_amount_per_order: 100,
            profits_quote: 0,
            protocol_fees_quote: 0,
            ask_prices: vec![1_000_000_000],
            ask_rev_prices: vec![900_000_000],
            ask_remaining: vec![100],
            ask_reverse_quote: vec![0],
            bid_prices: vec![1_000_000_000],
            bid_rev_prices: vec![1_100_000_000],
            bid_remaining_quote: vec![1000],
            bid_reverse_base: vec![0],
        }
    }

    #[test]
    fn test_apply_ask_bookkeeping_compound_adds_fee_to_reverse() {
        let mut grid = sample_grid(true);
        apply_ask_bookkeeping(&mut grid, 0, 10, 100, 1, 1_000_000_000).expect("ok");

        assert_eq!(grid.ask_remaining[0], 90);
        assert_eq!(grid.ask_reverse_quote[0], 101);
        assert_eq!(grid.profits_quote, 0);
    }

    #[test]
    fn test_apply_ask_bookkeeping_noncompound_caps_and_sends_overflow_to_profit() {
        let mut grid = sample_grid(false);
        // target quote = base_amount_per_order(100) * rev_price(0.9) = 90
        apply_ask_bookkeeping(&mut grid, 0, 10, 100, 5, 900_000_000).expect("ok");

        assert_eq!(grid.ask_reverse_quote[0], 90);
        assert_eq!(grid.profits_quote, 15);
    }

    #[test]
    fn test_apply_bid_bookkeeping_compound_reduces_less_quote() {
        let mut grid = sample_grid(true);
        apply_bid_bookkeeping(&mut grid, 0, 10, 100, 2).expect("ok");

        // compound keeps maker_fee inside order quote liquidity
        assert_eq!(grid.bid_remaining_quote[0], 902);
        assert_eq!(grid.bid_reverse_base[0], 10);
        assert_eq!(grid.profits_quote, 0);
    }

    #[test]
    fn test_apply_bid_bookkeeping_noncompound_puts_fee_into_profit() {
        let mut grid = sample_grid(false);
        apply_bid_bookkeeping(&mut grid, 0, 10, 100, 2).expect("ok");

        assert_eq!(grid.bid_remaining_quote[0], 900);
        assert_eq!(grid.bid_reverse_base[0], 10);
        assert_eq!(grid.profits_quote, 2);
    }

    #[test]
    fn test_apply_bid_reverse_bookkeeping_noncompound_caps_and_profit() {
        let mut grid = sample_grid(false);
        grid.bid_reverse_base[0] = 50;
        grid.bid_remaining_quote[0] = 80;
        apply_bid_reverse_bookkeeping(&mut grid, 0, 10, 100, 5, 1_000_000_000).expect("ok");

        assert_eq!(grid.bid_reverse_base[0], 40);
        assert_eq!(grid.bid_remaining_quote[0], 100);
        assert_eq!(grid.profits_quote, 85);
    }

    #[test]
    fn test_apply_ask_reverse_bookkeeping_compound() {
        let mut grid = sample_grid(true);
        grid.ask_reverse_quote[0] = 300;
        apply_ask_reverse_bookkeeping(&mut grid, 0, 10, 100, 2).expect("ok");

        assert_eq!(grid.ask_reverse_quote[0], 202);
        assert_eq!(grid.ask_remaining[0], 110);
        assert_eq!(grid.profits_quote, 0);
    }

    #[test]
    fn test_build_side_prices_linear_ask() {
        let prices = build_side_prices(
            1_000_000_000,
            3,
            &StrategyParam::Linear { gap: 100_000_000 },
            true,
        )
        .expect("ok");
        assert_eq!(prices, vec![1_000_000_000, 1_100_000_000, 1_200_000_000]);
    }

    #[test]
    fn test_build_side_prices_linear_bid() {
        let prices = build_side_prices(
            1_000_000_000,
            3,
            &StrategyParam::Linear { gap: -100_000_000 },
            false,
        )
        .expect("ok");
        assert_eq!(prices, vec![1_000_000_000, 900_000_000, 800_000_000]);
    }

    #[test]
    fn test_build_side_prices_geometry_ask() {
        let prices = build_side_prices(
            1_000_000_000,
            3,
            &StrategyParam::Geometry {
                ratio_x1e9: 1_100_000_000,
            },
            true,
        )
        .expect("ok");
        assert_eq!(prices, vec![1_000_000_000, 1_100_000_000, 1_210_000_000]);
    }

    #[test]
    fn test_build_side_prices_geometry_bid() {
        let prices = build_side_prices(
            1_000_000_000,
            3,
            &StrategyParam::Geometry {
                ratio_x1e9: 900_000_000,
            },
            false,
        )
        .expect("ok");
        assert_eq!(prices, vec![1_000_000_000, 900_000_000, 810_000_000]);
    }

    #[test]
    fn test_build_side_prices_reject_invalid_linear_sign() {
        let err = build_side_prices(
            1_000_000_000,
            2,
            &StrategyParam::Linear { gap: -1 },
            true,
        )
        .expect_err("must fail");
        assert_eq!(err, GridError::InvalidOrderCount.into());
    }

    #[test]
    fn test_build_side_prices_reject_invalid_geometry_ratio() {
        let err = build_side_prices(
            1_000_000_000,
            2,
            &StrategyParam::Geometry {
                ratio_x1e9: PRICE_SCALE,
            },
            true,
        )
        .expect_err("must fail");
        assert_eq!(err, GridError::InvalidOrderCount.into());
    }

    #[test]
    fn test_build_side_prices_zero_count() {
        let prices = build_side_prices(
            1_000_000_000,
            0,
            &StrategyParam::Linear { gap: 1 },
            true,
        )
        .expect("ok");
        assert!(prices.is_empty());
    }

    #[test]
    fn test_build_side_prices_reject_zero_price0() {
        let err = build_side_prices(0, 1, &StrategyParam::Linear { gap: 1 }, true).expect_err("must fail");
        assert_eq!(err, GridError::InvalidOrderCount.into());
    }

    #[test]
    fn test_build_side_prices_reject_too_many_orders() {
        let err = build_side_prices(
            1_000_000_000,
            (MAX_ORDERS_PER_SIDE + 1) as u8,
            &StrategyParam::Linear { gap: 1 },
            true,
        )
        .expect_err("must fail");
        assert_eq!(err, GridError::InvalidOrderCount.into());
    }

    #[test]
    fn test_build_side_prices_reject_linear_bid_non_positive_last_price() {
        let err = build_side_prices(1, 2, &StrategyParam::Linear { gap: -2 }, false).expect_err("must fail");
        assert_eq!(err, GridError::InvalidOrderCount.into());
    }

    #[test]
    fn test_build_side_reverse_prices_linear_ask() {
        let side = vec![1_000_000_000, 1_100_000_000, 1_200_000_000];
        let rev = build_side_reverse_prices(
            1_000_000_000,
            3,
            &StrategyParam::Linear { gap: 100_000_000 },
            true,
            &side,
        )
        .expect("ok");
        assert_eq!(rev, vec![900_000_000, 1_000_000_000, 1_100_000_000]);
    }

    #[test]
    fn test_build_side_reverse_prices_geometry_bid() {
        let side = vec![1_000_000_000, 900_000_000, 810_000_000];
        let rev = build_side_reverse_prices(
            1_000_000_000,
            3,
            &StrategyParam::Geometry {
                ratio_x1e9: 900_000_000,
            },
            false,
            &side,
        )
        .expect("ok");
        assert_eq!(rev, vec![1_111_111_111, 1_000_000_000, 900_000_000]);
    }

    #[test]
    fn test_build_side_reverse_prices_reject_mismatched_len() {
        let err = build_side_reverse_prices(
            1_000_000_000,
            2,
            &StrategyParam::Linear { gap: 100_000_000 },
            true,
            &[1_000_000_000],
        )
        .expect_err("must fail");
        assert_eq!(err, GridError::InvalidOrderCount.into());
    }

    #[test]
    fn test_build_side_reverse_prices_reject_invalid_first_price() {
        let err = build_side_reverse_prices(
            1,
            2,
            &StrategyParam::Linear { gap: 2 },
            true,
            &[1, 3],
        )
        .expect_err("must fail");
        assert_eq!(err, GridError::InvalidOrderCount.into());
    }

    #[test]
    fn test_mul_div_u64_basic() {
        let out = mul_div_u64(3, 10, 2).expect("ok");
        assert_eq!(out, 15);
    }

    #[test]
    fn test_mul_div_u64_reject_zero_denom() {
        let err = mul_div_u64(1, 1, 0).expect_err("must fail");
        assert_eq!(err, GridError::MathOverflow.into());
    }

    #[test]
    fn test_calc_fee_u64_basic() {
        let fee = calc_fee_u64(10_000, 100).expect("ok");
        assert_eq!(fee, 100);
    }

    #[test]
    fn test_calc_fee_u64_zero_fee() {
        let fee = calc_fee_u64(10_000, 0).expect("ok");
        assert_eq!(fee, 0);
    }

    #[test]
    fn test_sum_u64_slice_basic() {
        let total = sum_u64_slice(&[1, 2, 3, 4]).expect("ok");
        assert_eq!(total, 10);
    }

    #[test]
    fn test_sum_u64_slice_overflow() {
        let err = sum_u64_slice(&[u64::MAX, 1]).expect_err("must fail");
        assert_eq!(err, GridError::MathOverflow.into());
    }

    #[test]
    fn test_apply_ask_bookkeeping_noncompound_all_to_profit_when_already_at_quota() {
        let mut grid = sample_grid(false);
        grid.ask_reverse_quote[0] = 90;
        apply_ask_bookkeeping(&mut grid, 0, 10, 50, 5, 900_000_000).expect("ok");
        assert_eq!(grid.ask_reverse_quote[0], 90);
        assert_eq!(grid.profits_quote, 55);
    }

    #[test]
    fn test_apply_bid_reverse_bookkeeping_compound() {
        let mut grid = sample_grid(true);
        grid.bid_reverse_base[0] = 30;
        grid.bid_remaining_quote[0] = 200;
        apply_bid_reverse_bookkeeping(&mut grid, 0, 10, 100, 3, 1_000_000_000).expect("ok");
        assert_eq!(grid.bid_reverse_base[0], 20);
        assert_eq!(grid.bid_remaining_quote[0], 303);
        assert_eq!(grid.profits_quote, 0);
    }

    #[test]
    fn test_apply_bid_reverse_bookkeeping_underflow_reverse_base() {
        let mut grid = sample_grid(false);
        grid.bid_reverse_base[0] = 5;
        let err = apply_bid_reverse_bookkeeping(&mut grid, 0, 10, 10, 0, 1_000_000_000).expect_err("must fail");
        assert_eq!(err, GridError::MathOverflow.into());
    }

    #[test]
    fn test_apply_ask_reverse_bookkeeping_noncompound_puts_fee_to_profit() {
        let mut grid = sample_grid(false);
        grid.ask_reverse_quote[0] = 200;
        apply_ask_reverse_bookkeeping(&mut grid, 0, 10, 100, 3).expect("ok");
        assert_eq!(grid.ask_reverse_quote[0], 100);
        assert_eq!(grid.ask_remaining[0], 110);
        assert_eq!(grid.profits_quote, 3);
    }

    #[test]
    fn test_apply_ask_reverse_bookkeeping_underflow_reverse_quote() {
        let mut grid = sample_grid(false);
        grid.ask_reverse_quote[0] = 20;
        let err = apply_ask_reverse_bookkeeping(&mut grid, 0, 10, 100, 0).expect_err("must fail");
        assert_eq!(err, GridError::MathOverflow.into());
    }

    #[test]
    fn test_apply_bid_bookkeeping_underflow_remaining_quote() {
        let mut grid = sample_grid(false);
        grid.bid_remaining_quote[0] = 20;
        let err = apply_bid_bookkeeping(&mut grid, 0, 10, 100, 0).expect_err("must fail");
        assert_eq!(err, GridError::MathOverflow.into());
    }
}
