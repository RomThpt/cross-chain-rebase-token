# Cross Chain Rebase Token

1. A protocol that allows user to deposit into a vault and in return, receiver rebase tokens that reprensent their underlying balance
2. Rebase Token -> balanceOf function is dynamic to show the changing balance with time.
 - Balance increases linearly with time
 - mint tokens to our users everytime they perform an action (minting, burning, transferring, or ... bridging)
3. Interest rate
    - Individually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposits into the vault
    - this global intereset can only decrease to incetivise/reward early adopters
  