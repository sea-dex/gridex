use pinocchio::error::ProgramError;

#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GridError {
    InvalidInstruction = 1,
    NotAdmin = 2,
    NotGridOwner = 3,
    Paused = 4,
    GridCanceled = 5,
    InvalidFee = 6,
    InvalidOrderCount = 7,
    InvalidOrderIndex = 8,
    ZeroAmount = 9,
    MathOverflow = 10,
    InsufficientLiquidity = 11,
    NoProfits = 12,
    AccountDataTooSmall = 13,
    InvalidAccountOwner = 14,
    InvalidTokenProgram = 15,
    InvalidTokenAccount = 16,
}

impl From<GridError> for ProgramError {
    fn from(value: GridError) -> Self {
        ProgramError::Custom(value as u32)
    }
}
