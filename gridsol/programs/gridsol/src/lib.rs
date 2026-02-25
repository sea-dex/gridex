#![allow(clippy::result_large_err)]
#![allow(unexpected_cfgs)]

pub mod constants;
pub mod error;
pub mod instruction;
pub mod processor;
pub mod state;

use pinocchio::{entrypoint, AccountView, Address, ProgramResult};

entrypoint!(process_instruction);

fn process_instruction(
    program_id: &Address,
    accounts: &[AccountView],
    instruction_data: &[u8],
) -> ProgramResult {
    processor::process_instruction(program_id, accounts, instruction_data)
}
