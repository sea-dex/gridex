use borsh::{BorshDeserialize, BorshSerialize};

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub enum StrategyParam {
    Linear { gap: i64 },
    Geometry { ratio_x1e9: u64 },
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct CreateGridParams {
    pub signer_bump: u8,
    pub fee_bps: u16,
    pub compound: bool,
    pub oneshot: bool,
    pub base_amount_per_order: u64,
    pub ask_price0: u64,
    pub ask_count: u8,
    pub ask_strategy: StrategyParam,
    pub bid_price0: u64,
    pub bid_count: u8,
    pub bid_strategy: StrategyParam,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct FillOrderParams {
    pub side: u8, // taker side: 0 fillAsk (buy base), 1 fillBid (sell base)
    pub order_side: u8, // order book side: 0 ask order, 1 bid order
    pub order_index: u8,
    pub base_amount: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct FillTarget {
    pub side: u8, // taker side: 0 fillAsk (buy base), 1 fillBid (sell base)
    pub order_side: u8, // order book side: 0 ask order, 1 bid order
    pub order_index: u8,
    pub base_amount: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct FillOrdersParams {
    pub fills: Vec<FillTarget>,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct CancelOrderParams {
    pub side: u8, // 0 ask, 1 bid
    pub order_index: u8,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub enum GridInstruction {
    InitializeConfig {
        protocol_fee_bps: u16,
        oneshot_protocol_fee_bps: u16,
    },
    SetPause {
        paused: bool,
    },
    SetProtocolFee {
        protocol_fee_bps: u16,
    },
    SetOneshotProtocolFee {
        oneshot_protocol_fee_bps: u16,
    },
    CreateGrid(CreateGridParams),
    FillOrder(FillOrderParams),
    FillOrders(FillOrdersParams),
    CancelOrder(CancelOrderParams),
    CancelGrid,
    WithdrawProfits {
        amount: u64,
    },
    WithdrawProtocolFees {
        amount: u64,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_instruction_roundtrip_create_grid() {
        let ix = GridInstruction::CreateGrid(CreateGridParams {
            signer_bump: 254,
            fee_bps: 50,
            compound: true,
            oneshot: false,
            base_amount_per_order: 1_000_000,
            ask_price0: 1_100_000_000,
            ask_count: 2,
            ask_strategy: StrategyParam::Linear { gap: 100_000_000 },
            bid_price0: 900_000_000,
            bid_count: 2,
            bid_strategy: StrategyParam::Geometry { ratio_x1e9: 900_000_000 },
        });

        let data = borsh::to_vec(&ix).expect("serialize");
        let decoded = GridInstruction::try_from_slice(&data).expect("deserialize");

        match decoded {
            GridInstruction::CreateGrid(params) => {
                assert_eq!(params.signer_bump, 254);
                assert_eq!(params.fee_bps, 50);
                assert_eq!(params.base_amount_per_order, 1_000_000);
                assert_eq!(params.ask_price0, 1_100_000_000);
                assert_eq!(params.ask_count, 2);
                assert_eq!(params.bid_price0, 900_000_000);
                assert_eq!(params.bid_count, 2);
            }
            _ => panic!("unexpected variant"),
        }
    }

    #[test]
    fn test_instruction_roundtrip_fill_order() {
        let ix = GridInstruction::FillOrder(FillOrderParams {
            side: 1,
            order_side: 0,
            order_index: 3,
            base_amount: 42,
        });

        let data = borsh::to_vec(&ix).expect("serialize");
        let decoded = GridInstruction::try_from_slice(&data).expect("deserialize");

        match decoded {
            GridInstruction::FillOrder(params) => {
                assert_eq!(params.side, 1);
                assert_eq!(params.order_side, 0);
                assert_eq!(params.order_index, 3);
                assert_eq!(params.base_amount, 42);
            }
            _ => panic!("unexpected variant"),
        }
    }

    #[test]
    fn test_instruction_roundtrip_fill_orders() {
        let ix = GridInstruction::FillOrders(FillOrdersParams {
            fills: vec![
                FillTarget {
                    side: 0,
                    order_side: 0,
                    order_index: 1,
                    base_amount: 500,
                },
                FillTarget {
                    side: 1,
                    order_side: 1,
                    order_index: 2,
                    base_amount: 1_000,
                },
            ],
        });

        let data = borsh::to_vec(&ix).expect("serialize");
        let decoded = GridInstruction::try_from_slice(&data).expect("deserialize");

        match decoded {
            GridInstruction::FillOrders(params) => {
                assert_eq!(params.fills.len(), 2);
                assert_eq!(params.fills[0].side, 0);
                assert_eq!(params.fills[0].order_side, 0);
                assert_eq!(params.fills[0].order_index, 1);
                assert_eq!(params.fills[0].base_amount, 500);
                assert_eq!(params.fills[1].side, 1);
                assert_eq!(params.fills[1].order_side, 1);
                assert_eq!(params.fills[1].order_index, 2);
                assert_eq!(params.fills[1].base_amount, 1_000);
            }
            _ => panic!("unexpected variant"),
        }
    }

    #[test]
    fn test_instruction_roundtrip_cancel_order() {
        let ix = GridInstruction::CancelOrder(CancelOrderParams {
            side: 1,
            order_index: 5,
        });

        let data = borsh::to_vec(&ix).expect("serialize");
        let decoded = GridInstruction::try_from_slice(&data).expect("deserialize");

        match decoded {
            GridInstruction::CancelOrder(params) => {
                assert_eq!(params.side, 1);
                assert_eq!(params.order_index, 5);
            }
            _ => panic!("unexpected variant"),
        }
    }

    #[test]
    fn test_instruction_roundtrip_withdraw() {
        let ix = GridInstruction::WithdrawProfits { amount: 123_456 };
        let data = borsh::to_vec(&ix).expect("serialize");
        let decoded = GridInstruction::try_from_slice(&data).expect("deserialize");

        match decoded {
            GridInstruction::WithdrawProfits { amount } => assert_eq!(amount, 123_456),
            _ => panic!("unexpected variant"),
        }
    }

    #[test]
    fn test_instruction_roundtrip_withdraw_protocol_fees() {
        let ix = GridInstruction::WithdrawProtocolFees { amount: 888 };
        let data = borsh::to_vec(&ix).expect("serialize");
        let decoded = GridInstruction::try_from_slice(&data).expect("deserialize");

        match decoded {
            GridInstruction::WithdrawProtocolFees { amount } => assert_eq!(amount, 888),
            _ => panic!("unexpected variant"),
        }
    }
}
