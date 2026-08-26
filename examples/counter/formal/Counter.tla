------------------------------ MODULE Counter ------------------------------
EXTENDS Naturals

VARIABLES count, lastAction

vars == <<count, lastAction>>

Init ==
    /\ count = 0
    /\ lastAction = "Init"

Increment ==
    /\ count < 2
    /\ count' = count + 1
    /\ lastAction' = "Increment"

Next == Increment

Spec == Init /\ [][Next]_vars

\* These finite sets are both a TLC invariant and the source of the generated
\* Ada State_Type fields. The generator refuses to invent machine bounds.
TypeOK == count \in 0..2 /\ lastAction \in {"Init", "Increment"}

\* These record sets describe the typed boundary of one replayed transition.
HarnessInputType == [delta : 1..1]

HarnessOutcomeType == [accepted : BOOLEAN]

WitnessPending == count < 2

\* TLC serializes this reviewed projection. Every implementation-relevant
\* choice is materialized in input, and state includes every TLA+ VARIABLE.
Alias == [
    action |-> lastAction,
    role |-> "increment",
    input |-> [delta |-> 1],
    outcome |-> [accepted |-> TRUE],
    state |-> [count |-> count, lastAction |-> lastAction],
    model_source |-> lastAction
]

=============================================================================
