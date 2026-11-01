# SafeDeal

SafeDeal is a smart contract project for agreements between a client and a seller. The client deposits ETH into the contract, the seller marks the work as completed, and the client has a window to open a dispute before the seller can withdraw the payment.

Disputes are resolved by an arbitrator account selected when the agreement is created. If the arbitrator does not respond within the allotted time, the seller can withdraw the funds.

## Contracts

| Contract | Responsibility |
| --- | --- |
| `SafeDealFactory` | Creates an agreement and its referee contract, links them, and emits `DealCreated`. |
| `SafeDeal` | Holds the funds and enforces states, permissions, and deadlines. |
| `Referee` | Announces a dispute and allows the arbitrator account to submit a decision. |
| `IReferee` | Defines the notification function used by `SafeDeal`. |

Each Factory call creates a new `SafeDeal` and a new `Referee`. Creation and linking happen in a single transaction: if any step fails, the entire transaction reverts.

## Participants

- **Client:** pays, can cancel before payment, opens disputes, and withdraws authorized refunds.
- **Seller:** marks the work as completed and withdraws payment when permitted.
- **Arbitrator:** the account authorized to decide whether a dispute results in a client refund or a seller payment. It submits its decision through `Referee`.

The client, seller, and referee contract addresses are immutable in `SafeDeal`. The arbitrator account is immutable in `Referee`, and its agreement can only be assigned once by the Factory that created it.

## Agreement workflow

1. Any account can call `SafeDealFactory.createDeal(seller, client, arbitrator, price, duration)`.
2. The client calls `pay()`, sending exactly the agreed price. The work deadline starts at this point.
3. The seller calls `workDone()` before the deadline.
4. The client has **3 days** from delivery to open a dispute.
5. If no dispute is opened, the seller can withdraw payment once those 3 days have elapsed.
6. If a dispute is opened, the arbitrator has **3 days from its opening** to resolve it:
   - `Referee.resolveDispute(true)` authorizes a client refund.
   - `Referee.resolveDispute(false)` authorizes a seller payment.
7. The beneficiary requests the transfer through `returnFunds()` or `retireFunds()`. Resolving a dispute does not transfer the funds automatically.

If the seller does not mark the work as completed before the deadline, the client can recover the deposit through `returnFunds()` starting at the deadline.

### States and transitions

| Current state | Action or condition | Next state |
| --- | --- | --- |
| `AwaitingPayment` | The client pays the exact price | `Funded` |
| `AwaitingPayment` | The client cancels | `Canceled` |
| `Funded` | The seller marks delivery before the deadline | `WorkDone` |
| `Funded` | The client withdraws after the deadline without delivery | `Refunded` |
| `WorkDone` | The seller withdraws after the dispute window closes | `PaidOut` |
| `WorkDone` | The client opens a dispute within the dispute window | `Disputed` |
| `Disputed` | The arbitrator rules in favor of the client | `DisputeRefunded` |
| `Disputed` | The arbitrator rules in favor of the seller | `DisputeRejected` |
| `Disputed` | The seller withdraws after the arbitrator's deadline | `PaidOut` |
| `DisputeRefunded` | The client withdraws | `Refunded` |
| `DisputeRejected` | The seller withdraws | `PaidOut` |

`PaidOut`, `Refunded`, and `Canceled` are terminal states.

### Time boundaries

- `price` is expressed in **wei**, and `duration` in **seconds**.
- Work can only be marked as completed before `startDate + duration`.
- Refunds for missing delivery are available from `startDate + duration`, including that exact instant.
- A dispute can only be opened before `workDoneDate + 3 days`. From that instant, the seller can collect payment if no dispute is open.
- The current implementation allows resolution until `openDisputeDate + 3 days`, including that exact instant. Withdrawal due to arbitrator inactivity becomes available after that boundary.

The passage of time does not execute transactions or change the stored state. Each function checks the block timestamp when someone calls it.

## Events

| Contract | Event |
| --- | --- |
| `SafeDealFactory` | `DealCreated(address indexed deal, address indexed referee)` |
| `SafeDeal` | `ClientPayed(uint256 amount)` |
| `SafeDeal` | `WorkMarkedAsDone()` |
| `Referee` | `DisputeOpened(address indexed deal)` |

`DisputeOpened` records the notification on the blockchain. An application can listen for the event to notify the arbitrator; the contract does not send alerts or evaluate evidence itself.

## Local development

The project uses Solidity `^0.8.34` and Foundry. You need `forge` installed.

From the repository root, initialize the dependencies:

```sh
git submodule update --init --recursive
```

Build and run the tests:

```sh
forge build
forge test -vv
```

To run only the `SafeDeal` tests:

```sh
forge test --match-contract SafeDealTest -vv
```

Other useful commands:

```sh
forge coverage
forge test --gas-report
forge fmt --check
```

## Tests

The suite includes 48 tests: 41 for `SafeDeal`, 6 for `Referee`, and 1 for the Factory.

The `SafeDeal` tests cover:

- Constructor validation and participant permissions.
- Exact payment, incorrect amounts using fuzzing, and prevention of duplicate payments.
- Cancellation, delivery, and events.
- Exact boundaries of the work, review, and arbitration deadlines.
- Dispute opening, notification, and both arbitration outcomes.
- Withdrawal due to arbitrator inactivity and prevention of duplicate withdrawals.
- Reverts on failed notifications or transfers, and the ability to retry.
- Reentrancy attempts during payments and refunds.

## Current scope

The contract holds native ETH. It does not include token payments, partial fund allocation, evidence management, or a user interface. Arbitration is manual and depends on the selected account.

The Factory allows any nonzero arbitrator address; it currently does not prevent selecting the client or seller. If independence is required, the parties must verify that choice before funding the agreement.

Arbitrator inactivity favors the seller. This is a protocol rule, not verification that the work was completed correctly.

The project is under development and has not undergone a security audit. The tests verify the described cases, but do not replace an audit.
