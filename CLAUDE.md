# Project Rules
- take permission before applying changes to the coding files
## Comments
- Never remove comments from existing code
- If the related code is improved, update the comment to match
- If the related code is removed entirely, remove the comment with it

## Next Steps
- Always keep `md/NEXT_STEPS.md` updated after completing or starting any task

## User Flow
- Always keep `documentation/USER_FLOW.md` updated when any user interaction path changes, a new edge case is handled, or a new signal is added to the signal reference table
- Always keep `md/CHANGE_PASSWORD_DESIGN.md` updated

## writing the code
-in sv files always group the logical declaration of signals with the same number of bits into 1 statement
-do not use localparam
-when using an fsm use state_reg state_next
