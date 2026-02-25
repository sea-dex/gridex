use borsh::{BorshDeserialize, BorshSerialize};
use crate::constants::{MAX_ORDERS_PER_SIDE, MAX_PROTOCOL_FEE_BPS};

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct Config {
    pub admin: [u8; 32],
    pub paused: bool,
    pub protocol_fee_bps: u16,
    pub oneshot_protocol_fee_bps: u16,
    pub next_grid_id: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct Grid {
    pub owner: [u8; 32],
    pub id: u64,
    pub status: u8,
    pub base_vault: [u8; 32],
    pub quote_vault: [u8; 32],
    pub signer: [u8; 32],
    pub signer_bump: u8,
    pub fee_bps: u16,
    pub compound: bool,
    pub oneshot: bool,
    pub base_amount_per_order: u64,
    pub profits_quote: u64,
    pub protocol_fees_quote: u64,
    pub ask_prices: Vec<u64>,
    pub ask_rev_prices: Vec<u64>,
    pub ask_remaining: Vec<u64>,
    pub ask_reverse_quote: Vec<u64>,
    pub bid_prices: Vec<u64>,
    pub bid_rev_prices: Vec<u64>,
    pub bid_remaining_quote: Vec<u64>,
    pub bid_reverse_base: Vec<u64>,
}

impl Grid {
    pub fn is_active(&self) -> bool {
        self.status == 0
    }

    pub fn can_place(&self) -> bool {
        self.ask_prices.len() <= MAX_ORDERS_PER_SIDE && self.bid_prices.len() <= MAX_ORDERS_PER_SIDE
    }
}

pub fn split_fee(total_fee: u64, protocol_fee_bps: u16, oneshot_protocol_fee_bps: u16, oneshot: bool) -> (u64, u64) {
    let protocol_share_bps = if oneshot {
        oneshot_protocol_fee_bps.min(MAX_PROTOCOL_FEE_BPS)
    } else {
        protocol_fee_bps.min(MAX_PROTOCOL_FEE_BPS)
    } as u64;

    let protocol_fee = total_fee.saturating_mul(protocol_share_bps) / 10_000;
    let maker_fee = total_fee.saturating_sub(protocol_fee);
    (protocol_fee, maker_fee)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::MAX_ORDERS_PER_SIDE;

    fn sample_grid() -> Grid {
        Grid {
            owner: [1u8; 32],
            id: 1,
            status: 0,
            base_vault: [2u8; 32],
            quote_vault: [3u8; 32],
            signer: [4u8; 32],
            signer_bump: 200,
            fee_bps: 50,
            compound: false,
            oneshot: false,
            base_amount_per_order: 100,
            profits_quote: 0,
            protocol_fees_quote: 0,
            ask_prices: vec![1_000_000_000],
            ask_rev_prices: vec![900_000_000],
            ask_remaining: vec![100],
            ask_reverse_quote: vec![0],
            bid_prices: vec![900_000_000],
            bid_rev_prices: vec![1_000_000_000],
            bid_remaining_quote: vec![90],
            bid_reverse_base: vec![0],
        }
    }

    #[test]
    fn test_split_fee_normal() {
        let (protocol_fee, maker_fee) = split_fee(1_000, 200, 500, false);
        assert_eq!(protocol_fee, 20);
        assert_eq!(maker_fee, 980);
    }

    #[test]
    fn test_split_fee_oneshot_uses_oneshot_bps() {
        let (protocol_fee, maker_fee) = split_fee(1_000, 200, 800, true);
        assert_eq!(protocol_fee, 80);
        assert_eq!(maker_fee, 920);
    }

    #[test]
    fn test_split_fee_clips_by_max_protocol_fee_bps() {
        let (protocol_fee, maker_fee) = split_fee(1_000, 5_000, 5_000, false);
        assert_eq!(protocol_fee, 100);
        assert_eq!(maker_fee, 900);
    }

    #[test]
    fn test_grid_active_and_can_place() {
        let mut grid = sample_grid();
        assert!(grid.is_active());
        assert!(grid.can_place());

        grid.status = 1;
        assert!(!grid.is_active());
    }

    #[test]
    fn test_grid_can_place_rejects_too_many_orders() {
        let mut grid = sample_grid();
        grid.ask_prices = vec![1_000_000_000; MAX_ORDERS_PER_SIDE + 1];
        assert!(!grid.can_place());
    }

    #[test]
    fn test_grid_borsh_roundtrip() {
        let grid = sample_grid();
        let data = borsh::to_vec(&grid).expect("serialize");
        let decoded = Grid::try_from_slice(&data).expect("deserialize");
        assert_eq!(decoded.owner, [1u8; 32]);
        assert_eq!(decoded.signer_bump, 200);
        assert_eq!(decoded.ask_prices, vec![1_000_000_000]);
        assert_eq!(decoded.ask_rev_prices, vec![900_000_000]);
    }
}
